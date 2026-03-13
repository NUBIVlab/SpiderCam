#!/usr/bin/env python3
"""
png_to_p3_8bit_green.py
Convert any PNG (8/16-bit, any color type) to an 8-bit PPM P3 (ASCII),
using only the green channel (R=G=B=G). 16-bit inputs are explicitly scaled to 8-bit.

Usage:
    python png_to_p3_8bit_green.py input.png [output.ppm]

Requires:
    pip install pillow numpy
"""
import sys
import argparse
from pathlib import Path
from PIL import Image
import numpy as np

def _to_8bit_from_16bit_band(band: Image.Image) -> Image.Image:
    """Scale a 16-bit Pillow band to 8-bit L with round-half-up."""
    arr16 = np.array(band, dtype=np.uint16)          # shape (H, W)
    # scale to 0..255 with rounding
    arr8 = ((arr16.astype(np.uint32) * 255 + 32767) // 65535).astype(np.uint8)
    return Image.fromarray(arr8, mode="L")

def extract_green_8bit(im: Image.Image) -> Image.Image:
    """
    Return an 8-bit grayscale ('L') image containing the source's green channel.
    - If G exists, use it.
    - If grayscale, use that band.
    - If 16-bit data is present, scale explicitly to 8-bit.
    - Otherwise, fallback to RGB→G (8-bit).
    """
    bands = im.getbands()

    # 1) If there is a green band, extract it
    if 'G' in bands:
        g = im.getchannel('G')
        # Determine if it's effectively 16-bit (mode or extrema)
        maxv = g.getextrema()[1] if isinstance(g.getextrema(), tuple) else 255
        if g.mode.startswith("I;16") or maxv > 255:
            return _to_8bit_from_16bit_band(g)
        # Ensure 8-bit L
        return g.convert("L")

    # 2) Grayscale images (single band)
    if im.mode in ("I;16", "I;16B", "I;16L", "I"):
        # 16-bit grayscale
        return _to_8bit_from_16bit_band(im)
    if im.mode in ("L", "LA"):
        # 8-bit grayscale (ignore alpha if present)
        return im.getchannel(0).convert("L")

    # 3) Palette or other types: convert to 8-bit RGB then take G
    if im.mode == "P":
        im = im.convert("RGB")
        return im.getchannel('G').convert("L")

    # 4) Fallback: convert to RGB (8-bit) then take G
    im8 = im.convert("RGB")
    return im8.getchannel('G').convert("L")

def write_ppm_p3_8bit(path: Path, gray: Image.Image, pixels_per_line: int = 1):
    """
    Write a PPM P3 (ASCII) file at 'path' with maxval=255.
    Each pixel is written as "v v v" (R=G=B=gray).
    """
    w, h = gray.size
    maxval = 255
    it = gray.getdata()  # iterator of ints 0..255

    with open(path, "w", encoding="ascii") as f:
        # Header
        f.write("P3\n")
        f.write(f"{w} {h}\n")
        f.write(f"{maxval}\n")

        # Body
        per_line = max(1, int(pixels_per_line))
        count = 0
        for v in it:
            f.write(f"{v} {v} {v} ")
            count += 1
            if count == per_line:
                f.write("\n")
                count = 0
        if count:
            f.write("\n")

def convert_png_to_p3_8bit_green(inp: Path, outp: Path):
    im = Image.open(inp)
    g8 = extract_green_8bit(im)   # 8-bit 'L', scaled if needed
    write_ppm_p3_8bit(outp, g8)

def main():
    ap = argparse.ArgumentParser(description="Convert PNG to 8-bit PPM P3 using the green channel (scales 16-bit correctly).")
    ap.add_argument("input", help="Input PNG path")
    ap.add_argument("output", nargs="?", help="Output PPM path (defaults to input name with .ppm)")
    args = ap.parse_args()

    in_path = Path(args.input)
    if not in_path.exists():
        print(f"Error: {in_path} does not exist.", file=sys.stderr)
        sys.exit(1)

    out_path = Path(args.output) if args.output else in_path.with_suffix(".ppm")

    try:
        convert_png_to_p3_8bit_green(in_path, out_path)
    except Exception as e:
        print(f"Conversion failed: {e}", file=sys.stderr)
        sys.exit(2)

    print(f"Wrote {out_path}")

if __name__ == "__main__":
    main()
