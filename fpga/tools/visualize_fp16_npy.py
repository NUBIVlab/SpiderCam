#!/usr/bin/env python3
"""
visualize_fp16_npy.py
Load a float16 NumPy array (.npy), cast to float32, visualize with matplotlib,
choose colormap and value range.

Usage examples:
  python visualize_fp16_npy.py img.npy
  python visualize_fp16_npy.py img.npy --cmap magma --vmin 0.0 --vmax 1.0
  python visualize_fp16_npy.py img.npy --robust 2 98
  python visualize_fp16_npy.py img.npy --log --cmap inferno
  python visualize_fp16_npy.py img.npy --save out.png --dpi 200
"""

import argparse
from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.colors import Normalize, LogNorm

def main():
    p = argparse.ArgumentParser(description="Visualize float16 npy array (converted to float32) with colormap and value range control.")
    p.add_argument("npy", help="Input .npy file (dtype=float16 expected)")
    p.add_argument("--cmap", default="viridis", help="Matplotlib colormap (e.g., viridis, magma, gray)")
    p.add_argument("--vmin", type=float, default=None, help="Lower bound for color scaling")
    p.add_argument("--vmax", type=float, default=None, help="Upper bound for color scaling")
    p.add_argument("--robust", nargs=2, type=float, metavar=("PLOW","PHIGH"),
                   help="Use percentiles for scaling (e.g., --robust 2 98). Ignored if vmin/vmax set.")
    p.add_argument("--log", action="store_true", help="Use logarithmic normalization (values must be > 0)")
    p.add_argument("--title", default=None, help="Figure title")
    p.add_argument("--transpose", action="store_true", help="Transpose image before display")
    p.add_argument("--rotate90", action="store_true", help="Rotate image 90° CCW before display")
    p.add_argument("--save", default=None, help="If set, save PNG to this path instead of showing")
    p.add_argument("--dpi", type=int, default=150, help="Save DPI for --save")
    args = p.parse_args()

    arr = np.load(args.npy, allow_pickle=False)

    # Always cast to float32 for stability
    arr = arr.astype(np.float16)

    if arr.ndim != 2:
        raise ValueError(f"Expected a 2D array, got shape {arr.shape}")

    img = arr
    if args.transpose:
        img = img.T
    if args.rotate90:
        img = np.rot90(img)


    # Plot
    plt.figure()
    im = plt.imshow(img, cmap=args.cmap, vmin=args.vmin, vmax=args.vmax)
    plt.colorbar(im)
    plt.title(args.title or Path(args.npy).name)
    plt.tight_layout()

    if args.save:
        plt.savefig(args.save, dpi=args.dpi, bbox_inches="tight")
        print(f"Saved {args.save}")
    else:
        plt.show()

if __name__ == "__main__":
    main()
