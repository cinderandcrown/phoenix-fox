#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Cinder and Crown LLC
"""Draws the Phoenix Fox app icon.

The shape and the colors are not written here. They are read out of the two Swift files
the app itself draws from, so the icon and the mark inside the app are the same drawing:

  OpenVision/Views/Design/Core/FoxMarkGeometry.swift   the outlines
  OpenVision/Views/Design/Core/BrandPalette.swift      the colors

Run it after changing either file:

  python3 scripts/make_app_icon.py

It needs Pillow (`pip install pillow`) to draw. Reading the Swift files does not.
"""

from __future__ import annotations

import argparse
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEOMETRY = ROOT / "OpenVision/Views/Design/Core/FoxMarkGeometry.swift"
PALETTE = ROOT / "OpenVision/Views/Design/Core/BrandPalette.swift"
ICON = ROOT / "OpenVision/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

SIZE = 1024
# The mark fills this much of the icon's width. Apple's icon grid keeps artwork clear of
# the rounded corners the system cuts; 0.74 leaves the ear tips inside that.
MARK_SCALE = 0.74

Point = tuple[float, float]


def number_list(source: str, name: str) -> list[float]:
    """The numbers in `static let NAME: [Double] = [ ... ]`."""
    match = re.search(rf"static let {name}: \[Double\] = \[(.*?)\]", source, re.S)
    if not match:
        raise ValueError(f"{name} is not in the geometry file")
    numbers = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", match.group(1))]
    if len(numbers) < 8 or (len(numbers) - 2) % 6:
        raise ValueError(f"{name} should be a start point and then six numbers a curve")
    return numbers


def color(source: str, name: str, dark: bool = True) -> tuple[int, int, int]:
    """The color declared as `static let NAME = BrandColor("...", ...)`."""
    match = re.search(rf"static let {name} = BrandColor\(\"[^\"]*\", (.*?)\)", source)
    if not match:
        raise ValueError(f"{name} is not in the palette file")
    values = dict(re.findall(r"(light|dark): 0x([0-9A-Fa-f]{6})", match.group(1)))
    single = re.fullmatch(r"0x([0-9A-Fa-f]{6})", match.group(1).strip())
    text = single.group(1) if single else values["dark" if dark else "light"]
    return tuple(int(text[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def mirrored(numbers: list[float]) -> list[float]:
    return [value if index % 2 else 1 - value for index, value in enumerate(numbers)]


def symmetric(half: list[float]) -> list[float]:
    """A right half that starts and ends on the center line, completed with its mirror."""
    points = [(half[i], half[i + 1]) for i in range(0, len(half), 2)]
    start, rest = points[0], points[1:]
    curves = [rest[i : i + 3] for i in range(0, len(rest), 3)]
    full = list(half)
    ends = [start] + [curve[2] for curve in curves]
    for index in range(len(curves) - 1, -1, -1):
        control1, control2, _ = curves[index]
        for x, y in (control2, control1, ends[index]):
            full += [1 - x, y]
    return full


def flatten(numbers: list[float], steps: int = 48) -> list[Point]:
    """Points along a closed outline of cubic curves."""
    points = [(numbers[i], numbers[i + 1]) for i in range(0, len(numbers), 2)]
    result = [points[0]]
    start = points[0]
    for index in range(1, len(points), 3):
        c1, c2, end = points[index : index + 3]
        for step in range(1, steps + 1):
            t = step / steps
            u = 1 - t
            result.append(
                (
                    u**3 * start[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t**3 * end[0],
                    u**3 * start[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t**3 * end[1],
                )
            )
        start = end
    return result


def outlines(geometry: str) -> dict[str, list[list[Point]]]:
    eye = number_list(geometry, "rightEye")
    return {
        "head": [flatten(symmetric(number_list(geometry, "headHalf")))],
        "blaze": [flatten(symmetric(number_list(geometry, "blazeHalf")))],
        "eyes": [flatten(eye), flatten(mirrored(eye))],
    }


def png_size_and_type(path: Path) -> tuple[int, int, int]:
    """Width, height, and PNG color type (2 is RGB with no alpha), read from the header."""
    header = path.read_bytes()[:26]
    if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"{path} is not a PNG")
    width, height = struct.unpack(">II", header[16:24])
    return width, height, header[25]


def render(size: int = SIZE, oversample: int = 3):
    """The icon as a Pillow image. App icons may not have transparency, so it is RGB."""
    from PIL import Image, ImageDraw, ImageFilter

    geometry, palette = GEOMETRY.read_text(), PALETTE.read_text()
    shapes = outlines(geometry)
    side = size * oversample

    def mask(polygons: list[list[Point]]):
        image = Image.new("L", (side, side), 0)
        draw = ImageDraw.Draw(image)
        for polygon in polygons:
            draw.polygon([((0.5 + (x - 0.5) * MARK_SCALE) * side, (0.5 + (y - 0.5) * MARK_SCALE) * side) for x, y in polygon], fill=255)
        return image

    def vertical(stops: list[tuple[float, tuple[int, int, int]]], top: float, bottom: float):
        column = Image.new("RGB", (1, side))
        for y in range(side):
            t = min(max((y / side - top) / (bottom - top), 0), 1)
            for (start, a), (end, b) in zip(stops, stops[1:]):
                if start <= t <= end:
                    part = (t - start) / (end - start) if end > start else 0
                    column.putpixel((0, y), tuple(round(a[i] + (b[i] - a[i]) * part) for i in range(3)))
                    break
        return column.resize((side, side))

    ember, flame, gold = (color(palette, name) for name in ("ember", "flame", "gold"))
    garnet, canvas, ink = color(palette, "garnet"), color(palette, "canvas"), color(palette, "onFire")
    cream = color(palette, "ink")

    icon = Image.new("RGB", (side, side), canvas)

    # Heat behind the face, so the mark sits in a glow and not on flat black.
    glow = Image.new("L", (side, side), 0)
    radius, center = int(side * 0.44), (side // 2, int(side * 0.56))
    ImageDraw.Draw(glow).ellipse((center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius), fill=130)
    glow = glow.filter(ImageFilter.GaussianBlur(side * 0.12))
    icon = Image.composite(Image.new("RGB", (side, side), garnet), icon, glow)

    top, bottom = 0.5 - MARK_SCALE / 2, 0.5 + MARK_SCALE / 2
    deep = tuple(round(garnet[i] + (ember[i] - garnet[i]) * 0.35) for i in range(3))
    icon.paste(vertical([(0, deep), (0.45, ember), (0.8, flame), (1, gold)], top, bottom), (0, 0), mask(shapes["head"]))
    icon.paste(vertical([(0, gold), (1, cream)], 0.45, bottom), (0, 0), mask(shapes["blaze"]))
    icon.paste(Image.new("RGB", (side, side), ink), (0, 0), mask(shapes["eyes"]))
    return icon.resize((size, size), Image.LANCZOS)


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, default=ICON, help="where to write the PNG")
    parser.add_argument("--size", type=int, default=SIZE)
    options = parser.parse_args(arguments)
    try:
        image = render(options.size)
    except ImportError:
        print("Drawing the icon needs Pillow: pip install pillow", file=sys.stderr)
        return 1
    image.save(options.out, optimize=True)
    print(f"Wrote {options.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
