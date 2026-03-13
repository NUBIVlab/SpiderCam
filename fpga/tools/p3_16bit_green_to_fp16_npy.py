#!/usr/bin/env python3
"""
p3_16bit_green_to_fp16_npy.py

Read a P3 ASCII PPM with 16-bit values (maxval=65535), 1 pixel per line (R G B),
extract the green channel, reinterpret its 16-bit integers as IEEE-754 half-precision
floats (no numeric conversion), and save as a NumPy .npy file (dtype=float16).

Usage:
    python p3_16bit_green_to_fp16_npy.py input.ppm [output.npy]
"""

import argparse
import sys
from pathlib import Path
import numpy as np

def token_stream(ppm_path):
    """Yield whitespace-separated tokens from a PPM file, stripping comments (#...)."""
    with open(ppm_path, "r", encoding="ascii", errors="strict") as f:
        for line in f:
            line = line.split('#', 1)[0]  # remove comments
            if not line.strip():
                continue
            for tok in line.split():
                yield tok

def parse_ppm_header(ts):
    """Parse P3 header and return (width, height, maxval)."""
    try:
        magic = next(ts)
    except StopIteration:
        raise ValueError("Unexpected end of file while reading magic number.")
    if magic != "P3":
        raise ValueError(f"Unsupported magic number {magic!r}. Expected 'P3'.")
    try:
        width = int(next(ts))
        height = int(next(ts))
        maxval = int(next(ts))
    except StopIteration:
        raise ValueError("Unexpected end of file while reading width/height/maxval.")
    if width <= 0 or height <= 0:
        raise ValueError(f"Invalid dimensions: {width}x{height}.")
    if not (1 <= maxval <= 65535):
        raise ValueError(f"Invalid maxval {maxval}; must be 1..65535.")
    return width, height, maxval

def read_green_channel_uint16(ts, width, height, maxval):
    """Read pixel data (R G B triplets), return np.uint16 array of green values."""
    npx = width * height
    greens = np.empty(npx, dtype=np.uint16)

    for i in range(npx):
        try:
            r = int(next(ts))
            g = int(next(ts))
            b = int(next(ts))
        except StopIteration:
            raise ValueError(f"PPM ended early while reading pixel {i}/{npx}.")
        if not (0 <= r <= maxval and 0 <= g <= maxval and 0 <= b <= maxval):
            raise ValueError(f"Sample out of range at pixel {i}: ({r},{g},{b}) with maxval {maxval}.")
        if maxval == 65535:
            greens[i] = g
        else:
            raise ValueError(f"Expected 16-bit PPM (maxval=65535); got maxval={maxval}.")
    return greens

def main():
    ap = argparse.ArgumentParser(description="P3 ASCII PPM (16-bit) → NumPy .npy float16 via green channel (bit reinterpret).")
    ap.add_argument("input_ppm", help="Input P3 ASCII PPM path (maxval must be 65535).")
    ap.add_argument("output_npy", nargs="?", help="Output .npy path (default: input basename with .npy)")
    args = ap.parse_args()

    in_path = Path(args.input_ppm)
    if args.output_npy:
        out_path = Path(args.output_npy)
    else:
        out_path = in_path.with_suffix(".npy")

    if not in_path.exists():
        print(f"Error: input file {in_path} not found.", file=sys.stderr)
        sys.exit(1)

    ts = token_stream(in_path)
    width, height, maxval = parse_ppm_header(ts)
    greens_u16 = read_green_channel_uint16(ts, width, height, maxval)

    greens_fp16 = greens_u16.view(np.float16)
    greens_fp16 = greens_fp16.reshape((height, width))

    np.save(out_path, greens_fp16)
    print(f"Saved {out_path} (shape={greens_fp16.shape}, dtype={greens_fp16.dtype}).")

if __name__ == "__main__":
    main()
