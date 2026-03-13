#!/usr/bin/env python3
"""
filter_threshold_viewer.py

Usage:
    python filter_threshold_viewer.py array.npy filter.npy [--vmin N] [--vmax N] [--cmap NAME]

- Loads two FP16 .npy files (must be the same shape).
- Keeps arr[i, j] only where filter[i, j] > threshold, else sets 0.
- Cleans up NaN/Inf values.
- Opens a Matplotlib window with a slider to adjust thresholding.
"""

import sys
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Slider
import argparse

def main():
    parser = argparse.ArgumentParser(description="Threshold array.npy using filter.npy values")
    parser.add_argument("array", help="Input array (.npy)")
    parser.add_argument("filter", help="Filter array (.npy)")
    parser.add_argument("--vmin", type=float, default=None,
                        help="Minimum value for display colormap scaling")
    parser.add_argument("--vmax", type=float, default=None,
                        help="Maximum value for display colormap scaling")
    parser.add_argument("--cmap", type=str, default="gray",
                        help="Matplotlib colormap name (default: gray)")
    args = parser.parse_args()

    # Load arrays
    arr = np.load(args.array).astype(np.float32)
    flt = np.load(args.filter).astype(np.float32)

    if arr.shape != flt.shape:
        raise ValueError(f"Array shapes must match, got {arr.shape} vs {flt.shape}")

    # Replace NaN/Inf with 0 for safe display
    arr = np.nan_to_num(arr, nan=0.0, posinf=0.0, neginf=0.0)
    flt = np.nan_to_num(flt, nan=0.0, posinf=0.0, neginf=0.0)

    # Initial threshold (mean of filter values)
    init_thresh = float(flt.mean())

    # Apply threshold
    thresholded = np.where(flt > init_thresh, arr, np.nan)

    # Figure setup
    fig, ax = plt.subplots()
    plt.subplots_adjust(bottom=0.25)

    img_disp = ax.imshow(thresholded,
                         cmap=args.cmap,
                         interpolation="nearest",
                         vmin=args.vmin,
                         vmax=args.vmax)
    ax.set_title(f"Threshold = {init_thresh:.2f}")
    plt.colorbar(img_disp, ax=ax, fraction=0.046, pad=0.04)

    # Slider
    ax_thresh = plt.axes([0.2, 0.1, 0.65, 0.03])
    slider = Slider(ax_thresh, "Threshold",
                    float(np.min(flt)), float(np.max(flt)),
                    valinit=init_thresh)

    def update(val):
        t = slider.val
        thresholded = np.where(flt > t, arr, np.nan)
        img_disp.set_data(thresholded)
        ax.set_title(f"Threshold = {t:.2f}")
        fig.canvas.draw_idle()

    slider.on_changed(update)
    plt.show()

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python filter_threshold_viewer.py array.npy filter.npy [--vmin N] [--vmax N] [--cmap NAME]")
        sys.exit(1)
    main()
