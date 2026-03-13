import ftd2xx as ft
import time
import sys
import numpy as np

from collections import deque

import os
import threading
import queue
import json
import argparse

from functools import partial


# New: Import PyQt for our GUI display
from PyQt5 import QtWidgets, QtGui, QtCore

def make_plaintext_box(n_lines: int = 5) -> QtWidgets.QPlainTextEdit:
    box = QtWidgets.QPlainTextEdit()
    box.setLineWrapMode(QtWidgets.QPlainTextEdit.NoWrap)

    # Use a monospace font (system default monospace)
    mono = QtGui.QFont("Courier New")  # works on most platforms
    mono.setStyleHint(QtGui.QFont.Monospace)
    box.setFont(mono)

    # Fill with default text: "1.00" repeated n times
    default_text = "\n".join(["1.00"] * n_lines)
    box.setPlainText(default_text)

    # Compute height for exactly n lines
    fm = QtGui.QFontMetrics(box.font())
    line_height = fm.lineSpacing()
    extra = int(box.contentsMargins().top() + box.contentsMargins().bottom()) + 6
    fixed_height = int(line_height * n_lines) + extra
    box.setFixedHeight(fixed_height - 150)

    box.setVerticalScrollBarPolicy(QtCore.Qt.ScrollBarAsNeeded)
    return box


# QDialog for "capture frames"
class CaptureDialog(QtWidgets.QDialog):
    def __init__(self, settings=None, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Capture Settings")

        now = time.localtime()
        default_filename = time.strftime("capture-%Y-%m-%d_%H-%M-%S", now)
        if (settings is None):
            settings = {"frames": 1, "format": "png", "filename": default_filename, "seperate_cameras": True, "subdirectory": False}

        layout = QtWidgets.QFormLayout(self)

        self.frames_spin = QtWidgets.QSpinBox()
        self.frames_spin.setValue(settings["frames"])

        self.format_combo = QtWidgets.QComboBox()
        self.format_combo.addItems(["png", "binary", "numpy", "pbm"])
        index = self.format_combo.findText(settings["format"], QtCore.Qt.MatchFixedString)
        if index >= 0: self.format_combo.setCurrentIndex(index)

        self.filename_edit = QtWidgets.QLineEdit(settings["filename"])

        self.seperate_cams_checkbox = QtWidgets.QCheckBox()
        self.seperate_cams_checkbox.setChecked(settings["seperate_cameras"])
        self.do_subdirectory_checkbox = QtWidgets.QCheckBox()
        self.do_subdirectory_checkbox.setChecked(settings["subdirectory"])

        layout.addRow("Number of frames:", self.frames_spin)
        layout.addRow("Capture format:", self.format_combo)
        layout.addRow("Save cameras seperately:", self.seperate_cams_checkbox)
        layout.addRow("Save in new subdir:", self.do_subdirectory_checkbox)
        layout.addRow("Filename:", self.filename_edit)

        btns = QtWidgets.QDialogButtonBox(QtWidgets.QDialogButtonBox.Ok | QtWidgets.QDialogButtonBox.Cancel)
        btns.accepted.connect(self.accept)
        btns.rejected.connect(self.reject)
        layout.addRow(btns)

    def get_values(self):
        return {
            #"frames": self.frames_spin.value(),
            "frames": 1,
            "format": self.format_combo.currentText(),
            "filename": self.filename_edit.text(),
            "seperate_cameras": self.seperate_cams_checkbox.isChecked(),
            "subdirectory": self.do_subdirectory_checkbox.isChecked()
        }


class ViewOptionsDialog(QtWidgets.QDialog):
    def __init__(self, current_scale=2, current_color="gray", parent=None):
        super().__init__(parent)
        self.setWindowTitle("Viewer Options")
        layout = QtWidgets.QFormLayout(self)

        self.scale_edit = QtWidgets.QLineEdit(str(current_scale))
        layout.addRow("View scale factor:", self.scale_edit)

        # Create radio buttons
        self.cm_radio1 = QtWidgets.QRadioButton("Grayscale View")
        self.cm_radio2 = QtWidgets.QRadioButton("Color Gradient View")
        layout.addWidget(self.cm_radio1)
        layout.addWidget(self.cm_radio2)

        # Group them so only one is selectable
        self.color_map_radios = QtWidgets.QButtonGroup(self)
        self.color_map_radios.addButton(self.cm_radio1, id=0)
        self.color_map_radios.addButton(self.cm_radio2, id=1)
        if (current_color == "color"): self.color_map_radios.button(1).setChecked(True)
        else: self.color_map_radios.button(0).setChecked(True)

        # Accept / reject button
        btns = QtWidgets.QDialogButtonBox(QtWidgets.QDialogButtonBox.Ok | QtWidgets.QDialogButtonBox.Cancel)
        btns.accepted.connect(self.accept)
        btns.rejected.connect(self.reject)
        layout.addRow(btns)

        # Connect signal
        #self.color_map_radios.buttonClicked[int].connect(self.radio_changed)

    def get_values(self):
        try:
            scale = float(self.scale_edit.text())
            colormap = "color" if (self.color_map_radios.checkedId() == 1) else "gray"
        except ValueError:
            scale = None
            colormap = "gray"
        return { "scale": scale, "colormap": colormap}

class CommandWriteWidget(QtWidgets.QWidget):
    write_command = QtCore.pyqtSignal(dict)  # Custom signal to send values to parent

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Command Write")
        layout = QtWidgets.QFormLayout(self)

        monospace_font = QtGui.QFontDatabase.systemFont(QtGui.QFontDatabase.FixedFont)

        self.command_address = QtWidgets.QLineEdit()
        self.command_address.setFont(monospace_font)
        layout.addRow("Command address (hex):", self.command_address)

        self.command_data = QtWidgets.QLineEdit()
        self.command_data.setFont(monospace_font)
        layout.addRow("Command data (hex):", self.command_data)

        write_btn = QtWidgets.QPushButton("Send Command (spacebar)")
        write_btn.clicked.connect(self.send_command)
        layout.addRow(write_btn)

        self.setLayout(layout)

    def send_command(self):
        values = self.get_values()
        if values is not None:
            self.write_command.emit(values)  # Emit values to parent without closing

    def get_values(self):
        try:
            addr_bytes = int(self.command_address.text(), 16).to_bytes(2, 'little')
            data_bytes = int(self.command_data.text(), 16).to_bytes(4, 'little')
        except ValueError:
            QtWidgets.QMessageBox.warning(
                self, "Invalid Input",
                "addr must be 2 bytes of hex and data must be 4 bytes of hex"
            )
            return None

        return {"bytes": data_bytes + addr_bytes}

import re

class HomographyWidget(QtWidgets.QWidget):
    write_command = QtCore.pyqtSignal(dict)

    def __init__(self, start_addr=0x10, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Send Homography")
        layout = QtWidgets.QVBoxLayout(self)

        self.start_addr = start_addr

        # Customizable instruction label
        self.label = QtWidgets.QLabel("Paste a 3x3 matrix below that follows python formatting.")
        self.label.setWordWrap(True)
        layout.addWidget(self.label)

        # Multi-line text input
        self.textedit = QtWidgets.QTextEdit()
        monospace = QtGui.QFontDatabase.systemFont(QtGui.QFontDatabase.FixedFont)
        self.textedit.setFont(monospace)
        self.textedit.setMinimumHeight(120)
        layout.addWidget(self.textedit)

        default_text = "[[ 1.0  0.0  0.0]\n [ 0.0  1.0  0.0]\n [ 0.0  0.0  1.0]]"
        self.textedit.setPlainText(default_text)

        # Button
        send_btn = QtWidgets.QPushButton("Send Homography (spacebar)")
        send_btn.clicked.connect(self.send_command)
        layout.addWidget(send_btn)

        self.setLayout(layout)

    def send_command(self):
        values = self.get_values()
        if values is not None: self.write_command.emit(values)

    def parse_matrix_string(self, s):
        # Extract all rows: anything inside brackets [...]
        rows = re.findall(r"\[([^\[\]]+)\]", s)
        if not rows:
            raise ValueError("No valid rows found")

        matrix = []
        for row in rows:
            # Split on whitespace, convert to float
            values = list(map(float, row.strip().split()))
            matrix.append(values)

        array = np.array(matrix, dtype=float)

        if array.ndim != 2 or not np.issubdtype(array.dtype, np.floating):
            raise ValueError("Input is not a valid 2D float matrix")

        return array

    # converts from a floating point number to a sq10.8 fixed-point number that's been sign-extended
    # to 32b and converted to bytes
    def float_to_s10_q_8(self, n: float):
        return (int(np.round(n * (1 << 8))) & 0xffff_ffff).to_bytes(4, 'little')

    def get_values(self):
        return_bytes = b""
        addr = self.start_addr

        matrix = self.parse_matrix_string(self.textedit.toPlainText())

        try:
            if (matrix.shape != (3, 3)):
                raise ValueError("Invalid matrix")
        except (ValueError, SyntaxError, TypeError) as e:
            QtWidgets.QMessageBox.warning(
                self, "Invalid Input",
                "Matrix must be a 3x3 matrix of floats."
            )
            return None

        for row in matrix:
            for elt in row:
                return_bytes += self.float_to_s10_q_8(elt) + int(addr).to_bytes(2, 'little')
                addr += 1

        return {"bytes": return_bytes}

class RoiSendWidget(QtWidgets.QWidget):
    write_command = QtCore.pyqtSignal(dict)  # Custom signal to send values to parent

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Send ROI")
        layout = QtWidgets.QFormLayout(self)

        monospace_font = QtGui.QFontDatabase.systemFont(QtGui.QFontDatabase.FixedFont)

        self.roi_x = QtWidgets.QLineEdit()
        self.roi_x.setFont(monospace_font)
        layout.addRow("x (int):", self.roi_x)

        self.roi_y = QtWidgets.QLineEdit()
        self.roi_y.setFont(monospace_font)
        layout.addRow("y (int):", self.roi_y)

        send_pre_btn = QtWidgets.QPushButton("Set pre-bilinear-transform ROI")
        send_pre_btn.clicked.connect(lambda: self.send_roi_command(start_addr=0x80))
        layout.addRow(send_pre_btn)

        send_post_btn = QtWidgets.QPushButton("Set post-bilinear-transform ROI")
        send_post_btn.clicked.connect(lambda: self.send_roi_command(start_addr=0x82))
        layout.addRow(send_post_btn)

        self.setLayout(layout)

    def send_roi_command(self, start_addr=0x80):
        values = self.get_values(start_addr)
        if values is not None:
            self.write_command.emit(values)

    def get_values(self, start_addr=0x80):
        try:
            x = int(self.roi_x.text())
            y = int(self.roi_y.text())
            if x < 0 or y < 0:
                raise ValueError
            x_bytes = x.to_bytes(4, 'little')
            y_bytes = y.to_bytes(4, 'little')
        except ValueError:
            QtWidgets.QMessageBox.warning(
                self, "Invalid Input",
                "x and y must be positive integers"
            )
            return None

        addrs = [int(start_addr).to_bytes(2, 'little'), int(start_addr + 1).to_bytes(2, 'little')]

        return {"bytes": y_bytes + addrs[0] + x_bytes + addrs[1]}


class DfddParametersSendWidget(QtWidgets.QWidget):
    write_command = QtCore.pyqtSignal(dict)  # Custom signal to send values to parent

    # bits allocated to fractional portion of fixed point number for constants A and B.
    # check out verilog file containing package single_core_dfdd_fp_consts for source.
    FP_N_K = 12

    # bits allocated to fractional portion of fixed point number for constant threshold
    FP_N_THRESH = 0

    # addresses for constants in FPGA "command-mapped memory space"
    A_ADDRESS = 0x01
    B_ADDRESS = 0x02
    CONF_THRESHOLD_ADDRESS = 0x50

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Set DfDD Parameters")

        # ========== NEW TOP-LEVEL LAYOUT: grid with 2 columns ==========
        grid = QtWidgets.QGridLayout(self)
        col_left  = QtWidgets.QFormLayout()
        col_right = QtWidgets.QFormLayout()
        grid.addLayout(col_left,  0, 0)
        grid.addLayout(col_right, 0, 1)

        monospace_font = QtGui.QFontDatabase.systemFont(QtGui.QFontDatabase.FixedFont)

        self.title_s     = ["Scale 0", "Scale 1"]
        self.a_s         = [None, None]
        self.b_s         = [None, None]
        self.w0_s        = [None, None]
        self.w1_s        = [None, None]
        self.w2_s        = [None, None]

        self.col_center = None
        self.row_center = None
        self.r_squared  = None

        # You reuse self.confidence in your current code; keep it, but ALSO keep stable refs:
        self.confidence = None
        self.confidence_min = None
        self.depth_max = None
        self.depth_min = None

        self.a_base_addresses     = [0xa0, 0x90]
        self.b_base_addresses     = [0xb0, 0xf0]
        self.w0_base_addresses    = [0xc0, 0xc1]
        self.w1_base_addresses    = [0xd0, 0xd1]
        self.w2_base_addresses    = [0xe0, 0xe1]

        self.col_center_address     = 0x60
        self.row_center_address     = 0x61
        self.r_squared_base_address = 0x70

        self.confidence_address = 0x50
        self.depth_address      = 0x00
        self.depth_min_address  = 0x30

        self.no_zones = 16

        # Helper to pick column layout by scale
        def target_form(scale: int) -> QtWidgets.QFormLayout:
            return col_left if scale == 0 else col_right

        for scale in range(0, 2):
            form = target_form(scale)

            # Title
            self.title_s[scale] = QtWidgets.QLabel(self.title_s[scale])
            self.title_s[scale].setFont(QtGui.QFont("Arial", 12, QtGui.QFont.Bold))
            form.addRow(self.title_s[scale])

            # A
            self.a_s[scale] = [QtWidgets.QHBoxLayout(), make_plaintext_box(self.no_zones), QtWidgets.QPushButton("Set A")]
            row =      self.a_s[scale][0]
            text_box = self.a_s[scale][1]
            button   = self.a_s[scale][2]
            button.clicked.connect(partial(self.send_dfdd_parameter_block, True, self.a_base_addresses[scale], text_box, self.no_zones))
            row.addWidget(text_box)
            row.addWidget(button)
            form.addRow(row)

            # B
            self.b_s[scale] = [QtWidgets.QHBoxLayout(), make_plaintext_box(self.no_zones), QtWidgets.QPushButton("Set B")]
            row =      self.b_s[scale][0]
            text_box = self.b_s[scale][1]
            button   = self.b_s[scale][2]
            button.clicked.connect(partial(self.send_dfdd_parameter_block, True, self.b_base_addresses[scale], text_box, self.no_zones))
            row.addWidget(text_box)
            row.addWidget(button)
            form.addRow(row)

            # w0
            self.w0_s[scale] = [QtWidgets.QHBoxLayout(), QtWidgets.QLineEdit(), QtWidgets.QPushButton("Set w0")]
            row =      self.w0_s[scale][0]
            text_box = self.w0_s[scale][1]
            button   = self.w0_s[scale][2]
            text_box.setFont(monospace_font)
            text_box.setText("1.000")
            button.clicked.connect(partial(self.send_dfdd_parameter_block, True, self.w0_base_addresses[scale], text_box, 1))
            row.addWidget(text_box)
            row.addWidget(button)
            form.addRow(row)

            # w1
            self.w1_s[scale] = [QtWidgets.QHBoxLayout(), QtWidgets.QLineEdit(), QtWidgets.QPushButton("Set w1")]
            row =      self.w1_s[scale][0]
            text_box = self.w1_s[scale][1]
            button   = self.w1_s[scale][2]
            text_box.setFont(monospace_font)
            text_box.setText("1.000")
            button.clicked.connect(partial(self.send_dfdd_parameter_block, True, self.w1_base_addresses[scale], text_box, 1))
            row.addWidget(text_box)
            row.addWidget(button)
            form.addRow(row)

            # w2
            self.w2_s[scale] = [QtWidgets.QHBoxLayout(), QtWidgets.QLineEdit(), QtWidgets.QPushButton("Set w2")]
            row =      self.w2_s[scale][0]
            text_box = self.w2_s[scale][1]
            button   = self.w2_s[scale][2]
            text_box.setFont(monospace_font)
            text_box.setText("1.000")
            button.clicked.connect(partial(self.send_dfdd_parameter_block, True, self.w2_base_addresses[scale], text_box, 1))
            row.addWidget(text_box)
            row.addWidget(button)
            form.addRow(row)

        # ========== Bottom section spanning both columns ==========
        bottom = QtWidgets.QFormLayout()

        # Column and Row Center
        col_row_center_title = QtWidgets.QLabel("Column and Row Center")
        col_row_center_title.setFont(QtGui.QFont("Arial", 12, QtGui.QFont.Bold))
        bottom.addRow(col_row_center_title)

        self.col_center = [QtWidgets.QHBoxLayout(), QtWidgets.QLineEdit(), QtWidgets.QPushButton("Set Column Center")]
        row =      self.col_center[0]
        text_box = self.col_center[1]
        button   = self.col_center[2]
        text_box.setFont(monospace_font)
        text_box.setText("0")
        button.clicked.connect(partial(self.send_dfdd_parameter_block, False, self.col_center_address, text_box, 1))
        row.addWidget(text_box)
        row.addWidget(button)
        bottom.addRow(row)

        self.row_center = [QtWidgets.QHBoxLayout(), QtWidgets.QLineEdit(), QtWidgets.QPushButton("Set Row Center")]
        row =      self.row_center[0]
        text_box = self.row_center[1]
        button   = self.row_center[2]
        text_box.setFont(monospace_font)
        text_box.setText("0")
        button.clicked.connect(partial(self.send_dfdd_parameter_block, False, self.row_center_address, text_box, 1))
        row.addWidget(text_box)
        row.addWidget(button)
        bottom.addRow(row)

        # Radius Squared Values
        radius_squared_title = QtWidgets.QLabel("Radius Squared Values")
        radius_squared_title.setFont(QtGui.QFont("Arial", 12, QtGui.QFont.Bold))
        bottom.addRow(radius_squared_title)

        self.r_squared = [QtWidgets.QHBoxLayout(), make_plaintext_box(self.no_zones), QtWidgets.QPushButton("Set Radius²")]
        row =      self.r_squared[0]
        text_box = self.r_squared[1]
        button   = self.r_squared[2]
        button.clicked.connect(partial(self.send_dfdd_parameter_block, False, self.r_squared_base_address, text_box, self.no_zones))
        row.addWidget(text_box)
        row.addWidget(button)
        bottom.addRow(row)

        # Confidence
        confidence_title = QtWidgets.QLabel("Confidence Minimums")
        confidence_title.setFont(QtGui.QFont("Arial", 12, QtGui.QFont.Bold))
        bottom.addRow(confidence_title)

        self.confidence =  [QtWidgets.QHBoxLayout(), make_plaintext_box(self.no_zones), QtWidgets.QPushButton("Set Confidence")]
        self.confidence_min = self.confidence  # ✅ stable ref for Defaults
        row =      self.confidence[0]
        text_box = self.confidence[1]
        button   = self.confidence[2]
        button.clicked.connect(partial(self.send_dfdd_parameter_block, True, self.confidence_address, text_box, self.no_zones))
        row.addWidget(text_box)
        row.addWidget(button)
        bottom.addRow(row)

        # Depth Maximum
        depth_title = QtWidgets.QLabel("Depth Maximums")
        depth_title.setFont(QtGui.QFont("Arial", 12, QtGui.QFont.Bold))
        bottom.addRow(depth_title)

        self.confidence =  [QtWidgets.QHBoxLayout(), make_plaintext_box(self.no_zones), QtWidgets.QPushButton("Set Depth")]
        self.depth_max = self.confidence  # ✅ stable ref for Defaults
        row =      self.confidence[0]
        text_box = self.confidence[1]
        button   = self.confidence[2]
        button.clicked.connect(partial(self.send_dfdd_parameter_block, True, self.depth_address, text_box, self.no_zones))
        row.addWidget(text_box)
        row.addWidget(button)
        bottom.addRow(row)

        # Depth Minimum
        depth_min_title = QtWidgets.QLabel("Depth Minimums")
        depth_min_title.setFont(QtGui.QFont("Arial", 12, QtGui.QFont.Bold))
        bottom.addRow(depth_min_title)

        self.confidence =  [QtWidgets.QHBoxLayout(), make_plaintext_box(self.no_zones), QtWidgets.QPushButton("Set Depth")]
        self.depth_min = self.confidence  # ✅ stable ref for Defaults
        row =      self.confidence[0]
        text_box = self.confidence[1]
        button   = self.confidence[2]
        button.clicked.connect(partial(self.send_dfdd_parameter_block, True, self.depth_min_address, text_box, self.no_zones))
        row.addWidget(text_box)
        row.addWidget(button)
        bottom.addRow(row)

        # Add bottom block spanning both columns
        grid.addLayout(bottom, 1, 0, 1, 2)

        # ✅ Defaults button spanning both columns
        defaults_btn = QtWidgets.QPushButton("Defaults")
        defaults_btn.clicked.connect(self.load_defaults_and_send)
        grid.addWidget(defaults_btn, 2, 0, 1, 2)

        self.setLayout(grid)

    # ===================== Defaults (JSON) =====================
    def _defaults_path(self) -> str:
        base_dir = os.path.dirname(os.path.abspath(__file__))
        return os.path.join(base_dir, "dfdd_defaults.json")

    def _set_multiline(self, widget, values, n):
        if values is None:
            return
        if isinstance(values, str):
            lines = values.splitlines()
        else:
            lines = [str(v) for v in list(values)]
        lines = lines[:int(n)]
        widget.setPlainText("\n".join(lines))

    def _set_single(self, widget, value):
        if value is None:
            return
        widget.setText(str(value))

    def load_defaults_and_send(self):
        path = self._defaults_path()
        if not os.path.exists(path):
            QtWidgets.QMessageBox.warning(
                self, "Defaults not found",
                f"Could not find defaults file:\n{path}"
            )
            return

        try:
            with open(path, "r", encoding="utf-8") as f:
                cfg = json.load(f)
        except Exception as e:
            QtWidgets.QMessageBox.warning(
                self, "Defaults error",
                f"Failed to read/parse JSON:\n{path}\n\n{e}"
            )
            return

        # Accept either:
        #   {"scales": [ { ... }, { ... } ]}
        # or {"scale0": {...}, "scale1": {...}}
        scales = cfg.get("scales", None)
        if scales is None:
            scales = [cfg.get("scale0", {}), cfg.get("scale1", {})]
        while len(scales) < 2:
            scales.append({})

        # --- Apply + send for each scale ---
        for s in range(2):
            sc = scales[s] if isinstance(scales[s], dict) else {}

            if "A" in sc:
                self._set_multiline(self.a_s[s][1], sc.get("A"), self.no_zones)
                self.send_dfdd_parameter_block(True, self.a_base_addresses[s], self.a_s[s][1], self.no_zones)

            if "B" in sc:
                self._set_multiline(self.b_s[s][1], sc.get("B"), self.no_zones)
                self.send_dfdd_parameter_block(True, self.b_base_addresses[s], self.b_s[s][1], self.no_zones)

            if "w0" in sc:
                self._set_single(self.w0_s[s][1], sc.get("w0"))
                self.send_dfdd_parameter_block(True, self.w0_base_addresses[s], self.w0_s[s][1], 1)

            if "w1" in sc:
                self._set_single(self.w1_s[s][1], sc.get("w1"))
                self.send_dfdd_parameter_block(True, self.w1_base_addresses[s], self.w1_s[s][1], 1)

            if "w2" in sc:
                self._set_single(self.w2_s[s][1], sc.get("w2"))
                self.send_dfdd_parameter_block(True, self.w2_base_addresses[s], self.w2_s[s][1], 1)

        # --- Apply + send globals ---
        g = cfg.get("global", cfg.get("globals", {}))
        if not isinstance(g, dict):
            g = {}

        if "col_center" in g:
            self._set_single(self.col_center[1], g.get("col_center"))
            self.send_dfdd_parameter_block(False, self.col_center_address, self.col_center[1], 1)

        if "row_center" in g:
            self._set_single(self.row_center[1], g.get("row_center"))
            self.send_dfdd_parameter_block(False, self.row_center_address, self.row_center[1], 1)

        if "r_squared" in g:
            self._set_multiline(self.r_squared[1], g.get("r_squared"), self.no_zones)
            self.send_dfdd_parameter_block(False, self.r_squared_base_address, self.r_squared[1], self.no_zones)

        if "confidence" in g and self.confidence_min is not None:
            self._set_multiline(self.confidence_min[1], g.get("confidence"), self.no_zones)
            self.send_dfdd_parameter_block(True, self.confidence_address, self.confidence_min[1], self.no_zones)

        if "depth_max" in g and self.depth_max is not None:
            self._set_multiline(self.depth_max[1], g.get("depth_max"), self.no_zones)
            self.send_dfdd_parameter_block(True, self.depth_address, self.depth_max[1], self.no_zones)

        if "depth_min" in g and self.depth_min is not None:
            self._set_multiline(self.depth_min[1], g.get("depth_min"), self.no_zones)
            self.send_dfdd_parameter_block(True, self.depth_min_address, self.depth_min[1], self.no_zones)

    # ===================== Existing send function (unchanged) =====================
    def send_dfdd_parameter_block(self, float_num, base_addr, text_box, n):
        """
        Parse up to n lines from text_box.
        Each line is sent individually as float16 with its own address.
        - base_addr: starting register address (int-like)
        - text_box:  QLineEdit (single) or QTextEdit/QPlainTextEdit (multi-line)
        - n: maximum number of lines to use
        """
        # Handle different Qt widget types
        if hasattr(text_box, "toPlainText"):   # QTextEdit / QPlainTextEdit
            lines = text_box.toPlainText().splitlines()
        else:                                  # QLineEdit fallback
            lines = str(text_box.text()).splitlines()

        base = int(base_addr)
        sent = 0

        for raw in lines:
            if sent >= int(n):
                break

            s = raw.strip()
            if not s:
                continue  # skip blank line, do not advance address
            try:
                val = float(s)
            except ValueError:
                continue  # skip invalid line

            # Pack as float16 (same encoding as your single-value function)
            val_u32 = 0
            if(float_num):
                val_fp16 = np.float16(val)
                val_u32  = np.uint32(val_fp16.view(np.uint16))
            else:
                val_u32 = np.uint32(val)

            addr = base + sent
            return_bytes = val_u32.tobytes() + int(addr).to_bytes(2, "little")

            # 🔑 Emit each value separately
            self.write_command.emit({"bytes": return_bytes})

            sent += 1
