# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Cinder and Crown LLC
"""Tests for make_app_icon.py: it reads the same shape and colors the app draws from."""

import importlib.util
import tempfile
import unittest
from pathlib import Path

import make_app_icon as icon

HAS_PILLOW = importlib.util.find_spec("PIL") is not None


class ReadingSwift(unittest.TestCase):
    def test_number_list_reads_a_swift_array(self):
        source = "static let headHalf: [Double] = [\n 0.5, 0.25,\n 1, 0, 1, 1, 0.5, 0.75, // chin\n]"
        self.assertEqual(icon.number_list(source, "headHalf"), [0.5, 0.25, 1, 0, 1, 1, 0.5, 0.75])

    def test_number_list_refuses_a_list_that_is_not_whole_curves(self):
        with self.assertRaises(ValueError):
            icon.number_list("static let headHalf: [Double] = [0, 0, 1, 1, 1]", "headHalf")
        with self.assertRaises(ValueError):
            icon.number_list("nothing here", "headHalf")

    def test_color_reads_one_value_or_a_light_and_dark_pair(self):
        source = (
            'static let ember = BrandColor("Ember", 0xFF5A1F)\n'
            'static let canvas = BrandColor("Canvas", light: 0xFBF5EE, dark: 0x0D0A09)\n'
        )
        self.assertEqual(icon.color(source, "ember"), (0xFF, 0x5A, 0x1F))
        self.assertEqual(icon.color(source, "canvas"), (0x0D, 0x0A, 0x09))
        self.assertEqual(icon.color(source, "canvas", dark=False), (0xFB, 0xF5, 0xEE))
        with self.assertRaises(ValueError):
            icon.color(source, "teal")

    def test_the_real_files_have_everything_the_icon_needs(self):
        geometry, palette = icon.GEOMETRY.read_text(), icon.PALETTE.read_text()
        for name in ("headHalf", "blazeHalf", "rightEye"):
            self.assertGreaterEqual(len(icon.number_list(geometry, name)), 8)
        for name in ("ember", "flame", "gold", "garnet", "canvas", "onFire", "ink"):
            self.assertEqual(len(icon.color(palette, name)), 3)


class Geometry(unittest.TestCase):
    def test_symmetric_closes_the_outline_on_the_center_line(self):
        half = [0.5, 0.0, 0.75, 0.0, 1.0, 0.25, 1.0, 0.5, 1.0, 0.75, 0.75, 1.0, 0.5, 1.0]
        full = icon.symmetric(half)
        self.assertEqual(len(full), 2 + 6 * 4)
        self.assertEqual(full[-2:], [0.5, 0.0])
        points = icon.flatten(full, steps=8)
        self.assertEqual(points[0], points[-1])
        # Every point has its mirror image.
        rounded = {(round(x, 9), round(y, 9)) for x, y in points}
        for x, y in points:
            self.assertIn((round(1 - x, 9), round(y, 9)), rounded)

    def test_mirrored_flips_only_x(self):
        self.assertEqual(icon.mirrored([0.25, 0.5, 1.0, 0.0]), [0.75, 0.5, 0.0, 0.0])

    def test_the_mark_stays_inside_the_unit_square(self):
        shapes = icon.outlines(icon.GEOMETRY.read_text())
        self.assertEqual({name: len(parts) for name, parts in shapes.items()}, {"head": 1, "blaze": 1, "eyes": 2})
        for parts in shapes.values():
            for polygon in parts:
                for x, y in polygon:
                    self.assertTrue(0 <= x <= 1 and 0 <= y <= 1, (x, y))


class TheIconInTheRepository(unittest.TestCase):
    def test_it_is_a_1024_square_with_no_transparency(self):
        # The App Store refuses an icon with an alpha channel. Color type 2 is plain RGB.
        self.assertEqual(icon.png_size_and_type(icon.ICON), (1024, 1024, 2))

    def test_a_file_that_is_not_a_png_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "not.png"
            path.write_bytes(b"GIF89a" + bytes(40))
            with self.assertRaises(ValueError):
                icon.png_size_and_type(path)


@unittest.skipUnless(HAS_PILLOW, "drawing needs Pillow")
class Drawing(unittest.TestCase):
    def test_the_face_is_fire_on_a_dark_ground(self):
        image = icon.render(size=128, oversample=2)
        self.assertEqual(image.mode, "RGB")
        self.assertEqual(image.size, (128, 128))
        corner = image.getpixel((2, 2))
        self.assertLess(max(corner), 60)
        cheek = image.getpixel((90, 64))
        self.assertGreater(cheek[0], 200)
        self.assertGreater(cheek[0], cheek[2] + 100)
        blaze = image.getpixel((64, 100))
        self.assertGreater(min(blaze[0], blaze[1]), 180)

    def test_the_icon_in_the_repository_is_what_the_script_draws(self):
        from PIL import Image, ImageChops

        drawn = icon.render()
        saved = Image.open(icon.ICON).convert("RGB")
        difference = ImageChops.difference(drawn, saved).getextrema()
        # A different Pillow may round a blended edge differently; the drawing is the same.
        self.assertLessEqual(max(high for _, high in difference), 8)

    def test_main_writes_the_file(self):
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder) / "icon.png"
            self.assertEqual(icon.main(["--out", str(out), "--size", "64"]), 0)
            self.assertEqual(icon.png_size_and_type(out), (64, 64, 2))


if __name__ == "__main__":
    unittest.main()
