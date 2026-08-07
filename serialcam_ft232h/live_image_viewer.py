#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Live Image Viewer

- Normal mode: matplotlib GUI with vmin/vmax, colormap radios, dtype radios.
- Fast mode: OpenCV window, jet colormap, uint8 input, pvmin=38, pvmax=141,
  colorbar labeled 0.3–1.1, and "NaN" semantics via value 0 -> white.
"""

from typing import Optional, Tuple
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import TextBox, RadioButtons
from matplotlib.colors import Normalize
import cv2


class LiveImageViewer:
    def __init__(
        self,
        shape: Tuple[int, int] = (400, 480),
        dtype=np.uint16,
        cmap: str = "gray",
        interpretation: str = "int",   # "int" | "float16-view" | "byte-decimal-view"
        vmin: Optional[float] = 0.0,
        vmax: Optional[float] = 255.0,
        title: str = "Live Image Viewer",
        fast: bool = False,
        interpolation: str = "nearest",
        blit: bool = False,            # accepted but ignored (we disable blitting)
    ):
        # --- initial data/state ---
        self._raw = np.zeros(shape, dtype=dtype)
        self._interpretation = interpretation
        self._cmap = cmap
        self._vmin = vmin
        self._vmax = vmax
        self._interpolation = interpolation
        self._fast = fast
        self._needs_cbar_refresh = True

        # No blitting: keep flags for API compatibility, but never use them
        self._blit = False
        self._bg = None

        # Guard flags (avoid callback recursion)
        self._updating_cmap = False
        self._updating_dtype = False

        # Normalize object (used only in matplotlib mode)
        self._norm: Optional[Normalize] = None

        # Common attributes
        self.fig = None
        self.ax_img = None
        self.im = None
        self.cbar = None

        # Fast mode (cv2) specific
        self._win_name = title
        self._cbar_img: Optional[np.ndarray] = None
        self._pvmin: Optional[int] = None
        self._pvmax: Optional[int] = None

        if self._fast:
            # --------- FAST MODE: OpenCV viewer ---------
            # We treat incoming data as uint8 intensities directly.
            self._interpretation = "byte-decimal-view"  # semantic only

            # Pixel-domain min/max (uint8)
            self._pvmin = 51.2
            self._pvmax = 128

            # Display labels for the colorbar (still 0.3–1.1)
            self._vmin = 0.4
            self._vmax = 1.0

            # Prepare colorbar image once
            self._build_cv2_colorbar()

            # Create named windows (they will appear on first imshow)
            cv2.namedWindow(self._win_name, cv2.WINDOW_NORMAL)
            cv2.namedWindow(self._win_name + " colorbar", cv2.WINDOW_NORMAL)

            return

        # --------- NORMAL (FULL UI) MODE: matplotlib ---------
        # Fixed normalization for this mode
        self._norm = Normalize(vmin=self._vmin, vmax=self._vmax, clip=True)

        # --- figure/layout ---
        self.fig = plt.figure(figsize=(12, 8.5), constrained_layout=True)
        mgr = getattr(self.fig.canvas, "manager", None)
        if mgr and hasattr(mgr, "set_window_title"):
            mgr.set_window_title(title)

        # Two columns: left image (~80%), right controls (~20%)
        outer = self.fig.add_gridspec(
            nrows=1, ncols=2,
            width_ratios=[4, 1],
            wspace=0.04
        )

        # Left: image axes
        self.ax_img = self.fig.add_subplot(outer[0, 0])
        self.ax_img.set_title(title)
        self.ax_img.set_axis_off()

        img = self._coerce_view(self._raw, self._interpretation)
        self.im = self.ax_img.imshow(
            img,
            cmap=self._cmap,
            norm=self._norm,                  # fixed Normalize
            interpolation=self._interpolation,
            animated=False,                   # ensure non-blitting
            aspect="equal",
        )

        # Colorbar created once; refresh only on user changes
        self.cbar = self.fig.colorbar(
            self.im, ax=self.ax_img, shrink=0.95, pad=0.01, fraction=0.02
        )

        # Right: stacked controls
        control_gs = outer[0, 1].subgridspec(
            nrows=6, ncols=1,
            height_ratios=[1.1, 1.1, 0.4, 2.2, 2.2, 0.9],
            hspace=0.35
        )

        # vmin / vmax TextBoxes
        self.ax_vmin = self.fig.add_subplot(control_gs[0, 0])
        self.ax_vmax = self.fig.add_subplot(control_gs[1, 0])
        self.tb_vmin = TextBox(self.ax_vmin, "vmin:", initial="" if self._vmin is None else str(self._vmin))
        self.tb_vmax = TextBox(self.ax_vmax, "vmax:", initial="" if self._vmax is None else str(self._vmax))
        self.tb_vmin.on_submit(self._on_submit_vmin)
        self.tb_vmax.on_submit(self._on_submit_vmax)
        try:
            for tb in (self.tb_vmin, self.tb_vmax):
                tb.text_disp.set_fontsize(8)
                tb.label.set_fontsize(8)
        except Exception:
            pass

        # Interpretation radios
        self.ax_dtype = self.fig.add_subplot(control_gs[3, 0])
        self.ax_dtype.set_title("Interpretation", fontsize=9, pad=6)
        self.rb_dtype = RadioButtons(
            self.ax_dtype,
            labels=["int", "float16-view", "byte-decimal-view"],
            active={"int": 0, "float16-view": 1, "byte-decimal-view": 2}.get(self._interpretation, 0),
        )
        self.rb_dtype.on_clicked(self._on_dtype_clicked)

        # Colormap radios
        self.ax_cmap = self.fig.add_subplot(control_gs[4, 0])
        self.ax_cmap.set_title("Colormap", fontsize=9, pad=6)
        self._cmap_options = ["gray", "viridis", "magma", "plasma", "inferno", "jet"]
        active_idx = self._cmap_options.index(self._cmap) if self._cmap in self._cmap_options else 0
        self.rb_cmap = RadioButtons(self.ax_cmap, labels=self._cmap_options, active=active_idx)
        self.rb_cmap.on_clicked(self._on_cmap_clicked)

        for txt in list(self.rb_dtype.labels) + list(self.rb_cmap.labels):
            txt.set_fontsize(8)

        # Keyboard shortcuts
        self.fig.canvas.mpl_connect("key_press_event", self._on_key)

        # Finalize initial layout, then disable recomputation for speed
        self.fig.canvas.draw()
        try:
            self.fig.set_constrained_layout(False)
        except Exception:
            pass

    # ---------- Public API ----------
    def show(self, *, block: bool = False):
        if self._fast:
            # In cv2 mode, there's no blocking show; caller should use cv2.waitKey().
            return
        plt.show(block=block)

    def update_image(self, array: np.ndarray, *, interpretation: Optional[str] = None,
                     vmin: Optional[float] = None, vmax: Optional[float] = None,
                     cmap: Optional[str] = None) -> None:
        # Convert reference; caller can ensure contiguity upstream if needed
        self._raw = np.asarray(array)

        if self._fast:
            # --------- FAST CV2 PATH ---------
            frame_color = self._cv2_prepare_frame(self._raw)
            cv2.imshow(self._win_name, frame_color)
            if self._cbar_img is not None:
                cv2.imshow(self._win_name + " colorbar", self._cbar_img)
            # NOTE: caller (e.g., demo) should call cv2.waitKey(1) per frame
            return

        # --------- NORMAL MATPLOTLIB PATH ---------
        if interpretation is not None and interpretation != self._interpretation:
            self._interpretation = interpretation

        # Only change normalization if explicitly requested (constant work)
        if (vmin is not None) or (vmax is not None):
            self._vmin = self._vmin if vmin is None else vmin
            self._vmax = self._vmax if vmax is None else vmax
            if self._norm is not None:
                self._norm.vmin = self._vmin
                self._norm.vmax = self._vmax
            self._needs_cbar_refresh = True

        if cmap is not None and cmap != self._cmap:
            self._cmap = cmap
            if self.im is not None:
                self.im.set_cmap(cmap)
            self._needs_cbar_refresh = True
            if hasattr(self, "rb_cmap") and hasattr(self, "_cmap_options") and cmap in self._cmap_options:
                idx = self._cmap_options.index(cmap)
                if idx != self.rb_cmap.active:
                    self.rb_cmap.set_active(idx)

        # Set new pixels (no autoscale)
        img = self._coerce_view(self._raw, self._interpretation)
        if self.im is not None:
            self.im.set_data(img)

        # Only refresh colorbar when needed (constant cost otherwise)
        if self._needs_cbar_refresh and self.cbar is not None:
            self.cbar.update_normal(self.im)
            self._needs_cbar_refresh = False

        # Single draw path (no blitting)
        if self.fig is not None:
            self.fig.canvas.draw_idle()

    def set_vmin_vmax(self, vmin: Optional[float], vmax: Optional[float]) -> None:
        if self._fast:
            # In fast mode, vmin/vmax are fixed by design for the display,
            # and the labels are already set. Ignore external changes.
            return

        self._vmin, self._vmax = vmin, vmax
        if self._norm is not None:
            self._norm.vmin, self._norm.vmax = vmin, vmax
        self._needs_cbar_refresh = True

        # UI elements exist only in non-fast mode
        if hasattr(self, "tb_vmin"):
            self.tb_vmin.set_val("" if vmin is None else str(vmin))
        if hasattr(self, "tb_vmax"):
            self.tb_vmax.set_val("" if vmax is None else str(vmax))

        if self.fig is not None:
            self.fig.canvas.draw_idle()

    def set_cmap(self, cmap: str) -> None:
        if cmap == self._cmap:
            return
        self._cmap = cmap
        if not self._fast and self.im is not None:
            self.im.set_cmap(cmap)
            self._needs_cbar_refresh = True
            if self.fig is not None:
                self.fig.canvas.draw_idle()

    def set_interpretation(self, interpretation: str) -> None:
        if interpretation not in ("int", "float16-view", "byte-decimal-view"):
            return
        if interpretation == self._interpretation:
            return
        self._interpretation = interpretation

        if self._fast:
            # cv2 mode: semantics only, but display mapping is fixed
            return

        # Prevent callback recursion when syncing the radio UI
        self._updating_dtype = True
        try:
            if hasattr(self, "rb_dtype"):
                idx = {"int": 0, "float16-view": 1, "byte-decimal-view": 2}[interpretation]
                if idx != self.rb_dtype.active:
                    self.rb_dtype.set_active(idx)
        finally:
            self._updating_dtype = False

        # Re-render image with new interpretation (no autoscan)
        img = self._coerce_view(self._raw, self._interpretation)
        if self.im is not None:
            self.im.set_data(img)

        if self._needs_cbar_refresh and self.cbar is not None:
            self.cbar.update_normal(self.im)
            self._needs_cbar_refresh = False

        if self.fig is not None:
            self.fig.canvas.draw_idle()

    # ---------- Internals: cv2 path ----------
    def _cv2_prepare_frame(self, arr: np.ndarray) -> np.ndarray:
        # Treat input directly as uint8 image
        a = np.asarray(arr)
        if a.dtype != np.uint8:
            a = a.astype(np.uint8)

        # "NaN" semantics: raw value 0 is considered invalid → white
        a[:20] = 0
        nan_mask = (a == 0)

        pvmin = self._pvmin
        pvmax = self._pvmax
        if pvmin is None or pvmax is None:
            # Fallback: use full range if somehow unset
            pvmin, pvmax = 0, 255

        # Convert to float for normalization
        val = a.astype(np.float32)

        # For "invalid" pixels (0), pretend they are at pvmin for colormap
        val[nan_mask] = float(pvmin)

        # Normalize to [0,1] based on pixel-domain vmin/vmax
        norm = (val - float(pvmin)) / float(pvmax - pvmin)
        norm = np.clip(norm, 0.0, 1.0)

        # Convert to 8-bit index for colormap
        img8 = (norm * 255.0).astype(np.uint8)

        # Apply jet colormap
        img_color = cv2.applyColorMap(img8, cv2.COLORMAP_JET)

        # NaN → white (pixels that were 0 in original)
        if nan_mask.any():
            img_color[nan_mask] = (255, 255, 255)

        return img_color

    def _build_cv2_colorbar(self):
        # Build vertical colorbar image using jet colormap
        # Colors correspond to the same mapping we use for frames:
        # pvmin (bottom, labeled 0.3) → pvmax (top, labeled 1.1)
        h = 256
        w = 40

        pvmin = self._pvmin if self._pvmin is not None else 0
        pvmax = self._pvmax if self._pvmax is not None else 255

        # Pixel values from top (pvmax) to bottom (pvmin)
        pix_vals = np.linspace(pvmax, pvmin, h, dtype=np.float32).reshape(h, 1)

        # Normalize to [0,1] using same formula as _cv2_prepare_frame
        norm = (pix_vals - float(pvmin)) / float(pvmax - pvmin)
        norm = np.clip(norm, 0.0, 1.0)
        idx = (norm * 255.0).astype(np.uint8)

        # Apply JET colormap
        cbar = cv2.applyColorMap(idx, cv2.COLORMAP_JET)
        cbar = cv2.resize(cbar, (w, h), interpolation=cv2.INTER_NEAREST)

        # Add labels using *display* values 0.3 and 1.1
        cv2.putText(
            cbar, f"{self._vmax:.1f}", (2, 15),
            cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1, cv2.LINE_AA
        )
        cv2.putText(
            cbar, f"{self._vmin:.1f}", (2, h - 5),
            cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1, cv2.LINE_AA
        )

        self._cbar_img = cbar

    # ---------- Internals: matplotlib path ----------
    def _coerce_view(self, arr: np.ndarray, interpretation: str) -> np.ndarray:
        a = np.asarray(arr)
        if interpretation == "int":
            return a
        elif interpretation == "float16-view":
            if a.dtype == np.uint16 or a.dtype == np.int16:
                return a.view(np.float16)
            if a.dtype == np.uint32 or a.dtype == np.int32:
                b = (a & 0xFFFF).astype(np.uint16)
                return b.view(np.float16)
            if a.dtype == np.uint8:
                if a.ndim != 2:
                    raise TypeError("float16-view expects a 2D array; got shape %r" % (a.shape,))
                if a.size % 2 != 0:
                    raise ValueError("Total number of bytes must be even to reinterpret as float16.")
                b = a.view(np.uint16)
                return b.view(np.float16)
            raise TypeError(f"Unsupported dtype {a.dtype} for float16-view")
        elif interpretation == "byte-decimal-view":
            b = (a.astype(np.float32) / (2 ** 7))
            b[a == 0] = np.nan
            return b
        else:
            raise ValueError(f"Unknown interpretation: {interpretation}")

    def _on_submit_vmin(self, text: str) -> None:
        v = self._parse_optional_float(text)
        self._vmin = v
        if self._norm is not None:
            self._norm.vmin = v
        self._needs_cbar_refresh = True
        if self.fig is not None:
            self.fig.canvas.draw_idle()

    def _on_submit_vmax(self, text: str) -> None:
        v = self._parse_optional_float(text)
        self._vmax = v
        if self._norm is not None:
            self._norm.vmax = v
        self._needs_cbar_refresh = True
        if self.fig is not None:
            self.fig.canvas.draw_idle()

    def _on_dtype_clicked(self, label: str) -> None:
        if getattr(self, "_updating_dtype", False):
            return
        self.set_interpretation(label)
        if self.fig is not None:
            self.fig.canvas.draw_idle()

    def _on_cmap_clicked(self, label: str) -> None:
        self.set_cmap(label)
        if self._needs_cbar_refresh and self.cbar is not None:
            self.cbar.update_normal(self.im)
            self._needs_cbar_refresh = False
        if self.fig is not None:
            self.fig.canvas.draw_idle()

    def _parse_optional_float(self, text: str) -> Optional[float]:
        t = text.strip()
        if t == "" or t.lower() in ("none", "auto"):
            return None
        try:
            return float(t)
        except ValueError:
            return None

    def _on_key(self, event) -> None:
        # Fast (cv2) mode does not bind this
        if event.key in ("c", "C"):
            labels = [t.get_text() for t in self.rb_cmap.labels]
            idx = labels.index(self._cmap) if self._cmap in labels else 0
            idx = (idx + 1) % len(labels)
            self.set_cmap(labels[idx])
            if self._needs_cbar_refresh and self.cbar is not None:
                self.cbar.update_normal(self.im)
                self._needs_cbar_refresh = False
            if self.fig is not None:
                self.fig.canvas.draw_idle()
        elif event.key in ("d", "D"):
            self.set_interpretation("float16-view" if self._interpretation == "int" else "int")
        elif event.key in ("r", "R"):
            # One-time autoscale from current frame, then fix it
            img = np.asarray(self.im.get_array(), dtype=float)
            finite = np.isfinite(img)
            if finite.any():
                vmin = float(np.nanmin(img[finite]))
                vmax = float(np.nanmax(img[finite]))
                self._vmin, self._vmax = vmin, vmax
                if self._norm is not None:
                    self._norm.vmin, self._norm.vmax = vmin, vmax
                self._needs_cbar_refresh = True
            if self.fig is not None:
                self.fig.canvas.draw_idle()


# ---------------- Demo ----------------
def _demo_stream(view_seconds: float = 10.0, channels: int = 1,
                 blit: bool = False, fast: bool = False) -> None:
    rng = np.random.default_rng(42)
    viewers = []
    for i in range(channels):
        v = LiveImageViewer(
            shape=(240, 320),
            dtype=np.uint8,     # good match for cv2 fast mode
            title=f"Viewer {i}",
            blit=blit,
            fast=fast,
        )
        viewers.append(v)

    if not fast:
        plt.ion()
        plt.show(block=False)

    import time
    t0 = time.time()
    base = rng.integers(0, 256, size=(240, 320), dtype=np.uint8)
    while time.time() - t0 < view_seconds:
        shift = int((time.time() - t0) * 60) % base.shape[1]
        frame = np.roll(base, shift=shift, axis=1)
        noise = rng.integers(0, 16, size=frame.shape, dtype=np.uint8)
        frame = (frame + noise).astype(np.uint8)

        # Introduce some zeros to see white "NaN" pixels:
        frame[0:20, 0:20] = 0

        for v in viewers:
            v.update_image(frame)

        if fast:
            # cv2 event processing
            if cv2.waitKey(1) & 0xFF == 27:  # ESC to quit
                break
        else:
            plt.pause(0.01)

    if fast:
        cv2.destroyAllWindows()
    else:
        plt.ioff()
        plt.show()


if __name__ == "__main__":
    # fast=True → OpenCV mode
    _demo_stream(view_seconds=10.0, channels=2, blit=True, fast=True)
