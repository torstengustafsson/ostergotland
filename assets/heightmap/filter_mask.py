#!/usr/bin/env python3
"""Apply a closing (dilation then erosion of the zero areas) followed by a
Gaussian smooth to the water mask viz.hh_aspect.png. The closing removes
isolated specks without net-expanding the result."""
import sys
from pathlib import Path

from PIL import Image, ImageFilter

DIR = Path(__file__).resolve().parent
SRC = DIR / "viz.hh_aspect.png"
DST = DIR / "viz.hh_aspect_filtered.png"


def stats(img: Image.Image) -> tuple:
    if img.mode in ("I", "I;16", "I;16B"):
        h = img.histogram()
        lo = next((i for i, c in enumerate(h) if c), 0)
        hi = len(h) - 1 - next((i for i, c in enumerate(reversed(h)) if c), 0)
        return lo, hi
    extrema = img.getextrema()
    return extrema[0], extrema[1]


def prepare(img: Image.Image) -> tuple:
    """Normalize the source for filtering. 16-bit containers whose data only
    spans 0-255 are downconverted to 8-bit so Godot samples 0..1 correctly."""
    if img.mode in ("I;16", "I;16B"):
        img = img.convert("I")
    if img.mode == "I":
        h = img.histogram()
        hi = len(h) - 1 - next((i for i, c in enumerate(reversed(h)) if c), 0)
        if hi <= 255:
            return img.point(lambda v: v).convert("L"), "L"
        return img, img.mode
    return img, img.mode


def main():
    dilation = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    sigma = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    erosion = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    if dilation < 3 or dilation % 2 == 0:
        print("NOTE: Dilation kernel not odd integer >= 3, running without dilation")
        dilation = 0
    if erosion < 3 or erosion % 2 == 0:
        print("NOTE: Erosion kernel not odd integer >= 3, running without erosion")
        erosion = 0
    if sigma < 0:
        print("NOTE: Sigma not > 0, running without smoothing")
        sigma = 0

    img = Image.open(SRC)
    original_mode = img.mode
    print(f"Loaded {SRC.name}: mode={original_mode}, size={img.size}, range={stats(img)}")

    img, out_mode = prepare(img)
    print(f"Filtering as mode={img.mode}, output will be {out_mode}")

    if dilation != 0:
        img = img.filter(ImageFilter.MinFilter(dilation))
    if erosion != 0:
        img = img.filter(ImageFilter.MaxFilter(erosion))
    if sigma != 0:
        img = img.filter(ImageFilter.GaussianBlur(sigma)) if sigma > 0 else img

    img.save(DST)
    print(f"Written {DST}: mode={out_mode}, range={stats(Image.open(DST))}")
    print(f"Args: dilation kernel={dilation}, gaussian sigma={sigma}, erosion kernel={erosion}")


if __name__ == "__main__":
    main()