#!/bin/python3

# Requires qt5

# Copyright (c) 2025 John Mamish

#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Some portions of this code were generated with an LLM.

import sys
import cv2
import numpy as np
from PyQt5 import QtWidgets, QtGui, QtCore
from PyQt5.QtCore import QSignalBlocker

class PreviewDialog(QtWidgets.QDialog):
    def __init__(self, img1: np.ndarray, warped: np.ndarray, npoints: int, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Preview Homography")
        self.img1 = img1
        self.img2 = warped
        # 0: img1 bottom; 1: img2 bottom
        self.front = 0
        # Overlay alpha
        self.alpha = 0.5
        # Zoom factor for preview
        self.zoom = 1.0

        # Layout
        vbox = QtWidgets.QVBoxLayout(self)
        # Scroll area to allow panning when zoomed
        scroll = QtWidgets.QScrollArea()
        scroll.setWidgetResizable(True)
        self.image_label = QtWidgets.QLabel()
        self.image_label.setAlignment(QtCore.Qt.AlignCenter)
        scroll.setWidget(self.image_label)
        vbox.addWidget(scroll)

        # Label
        vbox.addWidget(QtWidgets.QLabel(f"This homography generated with {npoints} coordinate pairs"))

        # Controls: Swap, Alpha slider, Zoom instructions
        controls = QtWidgets.QHBoxLayout()
        swap_btn = QtWidgets.QPushButton("Swap Order")
        swap_btn.clicked.connect(self.swap_images)
        controls.addWidget(swap_btn)

        # Opacity label and slider
        opacity_label = QtWidgets.QLabel("Opacity:")
        controls.addWidget(opacity_label)
        self.alpha_slider = QtWidgets.QSlider(QtCore.Qt.Horizontal)
        self.alpha_slider.setRange(0, 100)
        self.alpha_slider.setValue(int(self.alpha * 100))
        self.alpha_slider.valueChanged.connect(self.on_alpha_changed)
        controls.addWidget(self.alpha_slider)

        vbox.addLayout(controls)

        # Install wheel event filter for zooming
        self.installEventFilter(self)

        self.update_display()

    def update_display(self):
        # Determine bottom and top images
        img_b = self.img1 if self.front == 0 else self.img2
        img_t = self.img2 if self.front == 0 else self.img1
        # Convert to RGB
        b_rgb = cv2.cvtColor(img_b, cv2.COLOR_BGR2RGB)
        t_rgb = cv2.cvtColor(img_t, cv2.COLOR_BGR2RGB)
        # Apply zoom scaling
        h, w = b_rgb.shape[:2]
        zh, zw = max(1, int(h * self.zoom)), max(1, int(w * self.zoom))
        b_resized = cv2.resize(b_rgb, (zw, zh), interpolation=cv2.INTER_NEAREST)
        t_resized = cv2.resize(t_rgb, (zw, zh), interpolation=cv2.INTER_NEAREST)
        # Convert bottom to QPixmap
        qimg_b = QtGui.QImage(b_resized.data, zw, zh, 3*zw, QtGui.QImage.Format_RGB888)
        pix = QtGui.QPixmap.fromImage(qimg_b)
        # Composite top with alpha
        qimg_t = QtGui.QImage(t_resized.data, zw, zh, 3*zw, QtGui.QImage.Format_RGB888)
        pix_t = QtGui.QPixmap.fromImage(qimg_t)
        painter = QtGui.QPainter(pix)
        painter.setOpacity(self.alpha)
        painter.drawPixmap(0, 0, pix_t)
        painter.end()
        self.image_label.setPixmap(pix)

    def swap_images(self):
        self.front = 1 - self.front
        self.update_display()

    def on_alpha_changed(self, value: int):
        self.alpha = value / 100.0
        self.update_display()

    def eventFilter(self, obj, event):
        if event.type() == QtCore.QEvent.Wheel and (event.modifiers() & QtCore.Qt.ControlModifier):
            delta = event.angleDelta().y()
            # Zoom in/out
            factor = 1.1 if delta > 0 else (1/1.1)
            self.zoom = max(0.1, self.zoom * factor)
            self.update_display()
            return True
        return super().eventFilter(obj, event)

INSTRUCTION_STR = "This GUI can be used to make and test homographies between 2 images.\n" \
    "Press the 'load images' button to choose 2 images to view side-by-side. Click on the images to place homogrpahy points.\n" \
    "You can click on homography points on the images or in the list to the side to select them for deletion.\n" \
    "You can use ctrl+the scroll wheel to zoom the left or right images.\n\n" \
    "Press the 'Preview Homography' button to see a preview of the 2 images on top of each other and the 'Generate Homography' button to get the homograpy matrix\n"


class HomographyFinder(QtWidgets.QWidget):
    selectedidx: int = None     # Which index in the list is selected

    def __init__(self):
        super().__init__()
        # Independent zooms for each image
        self.zoom1 = 1.0
        self.zoom2 = 1.0
        self.coords1 = []
        self.coords2 = []
        self.init_ui()

    def init_ui(self):
        self.setWindowTitle("Homography Finder")
        layout = QtWidgets.QHBoxLayout(self)

        # Left image
        self.img1_label = QtWidgets.QLabel()
        self.img1_label.setAlignment(QtCore.Qt.AlignTop | QtCore.Qt.AlignLeft)
        self.img1_label.setMouseTracking(True)
        self.img1_label.installEventFilter(self)
        self.img1_label.mousePressEvent = self.click1
        self.img1_label.mouseMoveEvent = self.hover1

        scroll1 = QtWidgets.QScrollArea()
        scroll1.setWidgetResizable(True)
        scroll1.setWidget(self.img1_label)
        layout.addWidget(scroll1)

        # Right image
        self.img2_label = QtWidgets.QLabel()
        self.img2_label.setAlignment(QtCore.Qt.AlignTop | QtCore.Qt.AlignLeft)
        self.img2_label.setMouseTracking(True)
        self.img2_label.installEventFilter(self)
        self.img2_label.mousePressEvent = self.click2
        self.img2_label.mouseMoveEvent = self.hover2

        scroll2 = QtWidgets.QScrollArea()
        scroll2.setWidgetResizable(True)
        scroll2.setWidget(self.img2_label)
        layout.addWidget(scroll2)

        # Control panel, fixed width
        PANEL_WIDTH = 250
        panel = QtWidgets.QWidget()
        panel.setMaximumWidth(PANEL_WIDTH)
        vbox = QtWidgets.QVBoxLayout(panel)

        # Coordinate lists
        vbox.addWidget(QtWidgets.QLabel("Coordinates (Image 1)"))
        self.list1 = QtWidgets.QListWidget()
        self.list1.setMaximumWidth(PANEL_WIDTH)
        self.list1.currentRowChanged.connect(self.on_list1_selected)
        vbox.addWidget(self.list1)

        vbox.addWidget(QtWidgets.QLabel("Coordinates (Image 2)"))
        self.list2 = QtWidgets.QListWidget()
        self.list2.setMaximumWidth(PANEL_WIDTH)
        self.list2.currentRowChanged.connect(self.on_list2_selected)
        vbox.addWidget(self.list2)

        # Buttons
        for (text, slot) in [
            ("Delete Pair (⌫ / 'del')", self.delete_coords),
            ("Clear List", self.clear_lists),
            ("Load Images", self.load_images),
            ("Preview Homography", self.prev_homo),
            ("Generate Homography", self.gen_homo)
        ]:
            btn = QtWidgets.QPushButton(text)
            btn.clicked.connect(slot)
            vbox.addWidget(btn)

        vbox.addStretch()
        layout.addWidget(panel)
        self.setLayout(layout)

        # Label for zoom inputs
        # TODO
        self.instruction_label = QtWidgets.QLabel(INSTRUCTION_STR)
        self.instruction_label.setMaximumWidth(PANEL_WIDTH)
        self.instruction_label.setWordWrap(True)
        vbox.addWidget(self.instruction_label)

        # Zoom inputs
        self.zoom_label = QtWidgets.QLabel("Zoom (left / right):")
        self.zoom_label.setMaximumWidth(PANEL_WIDTH)
        vbox.addWidget(self.zoom_label)

        self.zoom_input1 = QtWidgets.QLineEdit("1.0")
        self.zoom_input1.setValidator(QtGui.QDoubleValidator(0.1, 10, 2))
        self.zoom_input1.returnPressed.connect(self.apply_zoom1)
        vbox.addWidget(self.zoom_input1)

        self.zoom_input2 = QtWidgets.QLineEdit("1.0")
        self.zoom_input2.setValidator(QtGui.QDoubleValidator(0.1, 10, 2))
        self.zoom_input2.returnPressed.connect(self.apply_zoom2)
        vbox.addWidget(self.zoom_input2)

        self.image1 = np.ones((500, 500, 3), np.uint8) * 255
        self.image2 = np.ones((500, 500, 3), np.uint8) * 255

        self.redraw()

    def load_images(self):
        f1, _ = QtWidgets.QFileDialog.getOpenFileName(self, "Select Image 1")
        f2, _ = QtWidgets.QFileDialog.getOpenFileName(self, "Select Image 2")
        if f1 and f2:
            self.image1 = cv2.imread(f1)
            self.image2 = cv2.imread(f2)
            self.redraw()

    def redraw(self):
        self.img1_label.mousePressEvent = self.click1
        self.img1_label.mouseMoveEvent = self.hover1
        self.img2_label.mousePressEvent = self.click2
        self.img2_label.mouseMoveEvent = self.hover2

        self.img1_label.setMouseTracking(True)
        self.img2_label.setMouseTracking(True)

        if self.image1 is None or self.image2 is None:
            return

        # Left
        pix1 = self._make_pix(self.image1, self.coords1, self.zoom1)
        self.img1_label.setPixmap(pix1)
        # Right
        pix2 = self._make_pix(self.image2, self.coords2, self.zoom2)
        self.img2_label.setPixmap(pix2)

    def _make_pix(self, img, coords, zoom):
        # Zoom
        h, w = img.shape[:2]
        zh, zw = int(h * zoom), int(w * zoom)
        resized = cv2.resize(img, (zw, zh), interpolation=cv2.INTER_NEAREST)
        # BGR->RGB
        rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
        qimg = QtGui.QImage(rgb.data, zw, zh, 3 * zw, QtGui.QImage.Format_RGB888)
        pix = QtGui.QPixmap.fromImage(qimg)
        # Draw green pixel squares
        painter = QtGui.QPainter(pix)
        pen = QtGui.QPen(QtCore.Qt.green)
        pen.setWidth(1)
        painter.setPen(pen)
        for x, y in coords:
            sx, sy = int(x * zoom), int(y * zoom)
            w, h = int(np.ceil(zoom)), int(np.ceil(zoom))
            painter.drawRect(sx, sy, w, h)
        try:
            pen = QtGui.QPen(QtCore.Qt.red)
            WID = 2
            pen.setWidth(2)
            painter.setPen(pen)
            xsel, ysel = coords[self.selectedidx]
            xsel, ysel = int(xsel * zoom), int(ysel * zoom)
            w, h = int(np.ceil(zoom)), int(np.ceil(zoom))
            painter.drawRect(xsel-(WID-1), ysel-(WID-1), w+(2*WID), h+(2*WID))
        except (IndexError, TypeError) as e:
            pass
            print(f"{self.selectedidx}")
            print(e)
        painter.end()
        return pix

    def apply_zoom1(self):
        try:
            self.zoom1 = float(self.zoom_input1.text())
        except ValueError:
            self.zoom1 = 1.0
        self.redraw()

    def apply_zoom2(self):
        try:
            self.zoom2 = float(self.zoom_input2.text())
        except ValueError:
            self.zoom2 = 1.0
        self.redraw()

    def click1(self, event):
        x = int(event.pos().x() / self.zoom1)
        y = int(event.pos().y() / self.zoom1)
        # Check to see if the coords are already in the list. If so, don't add them.
        coords = (x, y);        coordstr = f"{x}, {y}"
        if (coords not in self.coords1):
            self.coords1.append(coords)
            self.list1.addItem(coordstr)
        else:
            self.selectedidx = self.coords1.index(coords)
            self.list1.setCurrentRow(self.selectedidx)
        self.redraw()

    def click2(self, event):
        x = int(event.pos().x() / self.zoom2)
        y = int(event.pos().y() / self.zoom2)
        coords = (x, y);        coordstr = f"{x}, {y}"
        if (coords not in self.coords2):
            self.coords2.append(coords)
            self.list2.addItem(coordstr)
        else:
            self.selectedidx = self.coords2.index(coords)
            self.list2.setCurrentRow(self.selectedidx)
        self.redraw()

    def hover1(self, event):
        self.redraw()
        self._draw_hover(self.img1_label, event.pos(), self.zoom1)

    def hover2(self, event):
        self.redraw()
        self._draw_hover(self.img2_label, event.pos(), self.zoom2)

    def _draw_hover(self, label, pos, zoom):
        base = label.pixmap().copy()
        painter = QtGui.QPainter(base)
        pen = QtGui.QPen(QtGui.QColor(128, 0, 128))
        pen.setWidth(3)
        painter.setPen(pen)
        x = int(int(pos.x() / zoom) * zoom)
        y = int(int(pos.y() / zoom) * zoom)
        w, h = int(np.ceil(zoom)), int(np.ceil(zoom))
        painter.drawRect(x, y, w, h)
        painter.end()
        label.setPixmap(base)

    def eventFilter(self, obj, event):
        if (event.type() == QtCore.QEvent.Wheel and (event.modifiers() & QtCore.Qt.ControlModifier)):
            delta = event.angleDelta().y()
            if obj == self.img1_label:
                self.zoom1 *= 1.1 if delta > 0 else (1/1.1)
                self.zoom_input1.setText(f"{self.zoom1:.2f}")
            elif obj == self.img2_label:
                self.zoom2 *= 1.1 if delta > 0 else (1/1.1)
                self.zoom_input2.setText(f"{self.zoom2:.2f}")
            self.redraw()
            return True
        return super().eventFilter(obj, event)

    def on_list1_selected(self, row):
        if (row >= 0):
            self.selectedidx = row
            with QSignalBlocker(self.list2):
                self.list2.setCurrentRow(self.selectedidx)
            self.redraw()


    def on_list2_selected(self, row):
        if (row >= 0):
            self.selectedidx = row
            with QSignalBlocker(self.list1):
                self.list1.setCurrentRow(self.selectedidx)
            self.redraw()

    def clear_lists(self):
        self.coords1.clear()
        self.coords2.clear()
        self.list1.clear()
        self.list2.clear()
        self.redraw()

    def delete_coords(self):
        with QSignalBlocker(self.list1), QSignalBlocker(self.list2):
            try:
                self.coords1.pop(self.selectedidx)
                self.list1.takeItem(self.selectedidx)
            except (TypeError, IndexError) as e:
                pass

            try:
                self.coords2.pop(self.selectedidx)
                self.list2.takeItem(self.selectedidx)
            except (TypeError, IndexError) as e:
                pass

            self.selectedidx = None
            self.list1.setCurrentRow(-1)
            self.list2.setCurrentRow(-1)
            self.redraw()

    def _check_min_points_failed(self):
        MIN_POINTS = 5
        if (len(self.coords1) != len(self.coords2)):
            # Custom warning with monospace font
            msg = QtWidgets.QMessageBox(self)
            msg.setIcon(QtWidgets.QMessageBox.Warning)
            msg.setWindowTitle("Warning")
            msg.setText(
                f"The left and right images should have the same number of points selected to generate a homography. " +\
                f"The left image has {len(self.coords1)} points but the right image has {len(self.coords2)}. "+\
                f"Please select more points to generate a homography."
            )
            # Apply monospace font to the message text
            msg.setStyleSheet("QLabel{font-family: 'Courier New';}")
            msg.exec_()
            return True
        elif (len(self.coords1) < MIN_POINTS or len(self.coords2) < MIN_POINTS):
            # Custom warning with monospace font
            msg = QtWidgets.QMessageBox(self)
            msg.setIcon(QtWidgets.QMessageBox.Warning)
            msg.setWindowTitle("Warning")
            msg.setText(
                f"Select at least {MIN_POINTS} points before previewing homography. " +\
                f"You've only selected {len(self.coords1)} points so far. " +\
                f"More points give better results."
            )
            # Apply monospace font to the message text
            msg.setStyleSheet("QLabel{font-family: 'Courier New';}")
            msg.exec_()
            return True

        if (len(self.coords1) < 15):
            msg = QtWidgets.QMessageBox(self)
            msg.setIcon(QtWidgets.QMessageBox.Information)
            msg.setWindowTitle("Info")
            msg.setText(
                f"Your homography uses {len(self.coords1)} point pairs.\n" +\
                f"The more the better! If your homography doesn't look great, try adding more pairs."
            )

            # Apply monospace font to the message text
            msg.setStyleSheet("QLabel{font-family: 'Courier New';}")
            msg.exec_()

        return False

    def gen_homo(self):
        if (self._check_min_points_failed()): return
        H, _ = cv2.findHomography(
            np.array(self.coords1, dtype=np.float32),
            np.array(self.coords2, dtype=np.float32),
            cv2.RANSAC, 5.0
        )
        print("Homography Matrix:")
        print(H)
        QtWidgets.QMessageBox.warning(
            self,
            "Homography Matrix",
            f"{H}"
        )

    def prev_homo(self):
        if (self._check_min_points_failed()): return
        H, _ = cv2.findHomography(
            np.array(self.coords2, dtype=np.float32),
            np.array(self.coords1, dtype=np.float32),
            cv2.RANSAC, 5.0
        )
        warped = cv2.warpPerspective(
            self.image2, H,
            (self.image1.shape[1], self.image1.shape[0]),
            flags=cv2.INTER_NEAREST
        )
        dlg = PreviewDialog(self.image1, warped, len(self.coords1), self)
        dlg.exec_()

    def keyPressEvent(self, event):
        # Handle Delete or Backspace when main window focused
        if event.key() in (QtCore.Qt.Key_Delete, QtCore.Qt.Key_Backspace):
            row = self.list2.currentRow()
            if row is not None:
                self.delete_coords()

        super().keyPressEvent(event)

if __name__ == '__main__':
    app = QtWidgets.QApplication(sys.argv)
    window = HomographyFinder()
    window.show()
    sys.exit(app.exec_())
