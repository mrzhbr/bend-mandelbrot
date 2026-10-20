"""Dependency-free integration tests against the native Bend renderer."""

import math
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "build" / "mandelbrot"


def f32(value):
    return struct.unpack("f", struct.pack("f", value))[0]


def reference_sample(index, width, height, iterations, view, ox, oy):
    """Independent scalar oracle, rounding each operation to Bend's F32."""
    center_x, center_y, span = map(f32, view)
    scale = f32(span / width)
    cx = f32(f32(center_x - f32(span * 0.5)) + f32(f32(index % width + ox) * scale))
    cy = f32(
        f32(center_y + f32(f32(height * scale) * 0.5))
        - f32(f32(index // width + oy) * scale)
    )
    zx = zy = 0.0
    for step in range(1, iterations + 1):
        nx = f32(f32(f32(zx * zx) - f32(zy * zy)) + cx)
        ny = f32(f32(f32(2.0 * zx) * zy) + cy)
        zx, zy = nx, ny
        radius = f32(f32(zx * zx) + f32(zy * zy))
        if radius > 4.0:
            smooth = f32(step + 1.0 - f32(math.log2(f32(0.5 * f32(math.log(radius))))))
            phase = f32(smooth * f32(0.025))
            return tuple(
                int(f32(127.5 * f32(1.0 + f32(math.cos(f32(phase + f32(offset)))))))
                for offset in (0.8, 1.8, 3.3)
            )
    return (0, 0, 0)


def reference_pixel(index, width, height, iterations, view, grid=1):
    sums = [0, 0, 0]
    for y in range(grid):
        for x in range(grid):
            rgb = reference_sample(
                index,
                width,
                height,
                iterations,
                view,
                f32((x + 0.5) / grid),
                f32((y + 0.5) / grid),
            )
            for channel, value in enumerate(rgb):
                sums[channel] += value
    return tuple(value // (grid * grid) for value in sums)


class RendererTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bend-mandelbrot-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def invoke(self, args):
        return subprocess.run(
            [str(BINARY), "--threads", "4", *map(str, args)],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )

    def render(self, width, height, mode="parallel", iterations=80, view=None):
        path = self.directory / f"{mode}.ppm"
        args = [width, height, iterations, path, mode]
        if view is not None:
            args.extend(view)
        result = self.invoke(args)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Render time:", result.stdout)
        magic, dimensions, maximum, pixels = path.read_bytes().split(b"\n", 3)
        self.assertEqual(magic, b"P6")
        self.assertEqual(dimensions, f"{width} {height}".encode())
        self.assertEqual(maximum, b"255")
        self.assertEqual(len(pixels), width * height * 3)
        return pixels

    def test_modes_are_identical_for_odd_and_tiny_images(self):
        for width, height in [(35, 23), (1, 1), (1, 17), (17, 1)]:
            with self.subTest(width=width, height=height):
                self.assertEqual(
                    self.render(width, height, "sequential"),
                    self.render(width, height, "parallel"),
                )

    def test_pixels_match_independent_f32_reference(self):
        for view in [(-0.5, 0.0, 3.2), (-0.75, 0.1, 0.2)]:
            with self.subTest(view=view):
                width, height, iterations = 35, 23, 80
                pixels = self.render(width, height, iterations=iterations, view=view)
                for index in range(width * height):
                    expected = reference_pixel(index, width, height, iterations, view)
                    actual = pixels[index * 3 : index * 3 + 3]
                    self.assertTrue(
                        all(
                            abs(a - b) <= 1
                            for a, b in zip(actual, expected, strict=True)
                        ),
                        f"Pixel {index}: {tuple(actual)} != {expected}",
                    )

    def test_supersampling_matches_reference_and_parallel_mode(self):
        view = (-0.5, 0.0, 3.2)
        for grid in (2, 3, 4):
            with self.subTest(grid=grid):
                pixels = self.render(11, 7, view=(*view, grid))
                self.assertEqual(
                    pixels, self.render(11, 7, "sequential", view=(*view, grid))
                )
                for index in range(11 * 7):
                    expected = reference_pixel(index, 11, 7, 80, view, grid)
                    actual = pixels[index * 3 : index * 3 + 3]
                    self.assertTrue(
                        all(
                            abs(a - b) <= 1
                            for a, b in zip(actual, expected, strict=True)
                        )
                    )

    def test_larger_dimension_is_supported(self):
        self.render(8192, 1, iterations=1, view=(3, 0, 0.1))

    def test_interior_view_is_black(self):
        self.assertEqual(self.render(11, 7, view=(0, 0, 0.1)), bytes(11 * 7 * 3))

    def test_exterior_view_is_coloured(self):
        pixels = self.render(7, 5, view=(3, 0, 0.1))
        self.assertTrue(all(any(pixels[i : i + 3]) for i in range(0, len(pixels), 3)))

    def test_zoom_modes_are_identical(self):
        view = (-0.7435, 0.1314, 0.012)
        self.assertEqual(
            self.render(41, 29, "sequential", 500, view),
            self.render(41, 29, "parallel", 500, view),
        )

    def test_invalid_arguments_do_not_create_an_image(self):
        output = self.directory / "invalid.ppm"
        cases = [
            [0, 10, 20, output, "parallel"],
            [10, 0, 20, output, "parallel"],
            [10, 10, 0, output, "parallel"],
            [8193, 10, 20, output, "parallel"],
            [8192, 8192, 20, output, "parallel"],
            [10, 10, 10001, output, "parallel"],
            ["abc", 10, 20, output, "parallel"],
            ["4294967296", 10, 20, output, "parallel"],
            [10, 10, 20, output, "invalid"],
            [10, 10, 20, output, "parallel", 0, 0, 0],
            [10, 10, 20, output, "parallel", 0, 0, -1],
            [10, 10, 20, output, "parallel", "nan", 0, 1],
            [10, 10, 20, output, "parallel", 0, 0, "inf"],
            [10, 10, 20, output, "parallel", 0, 0, 1, 0],
            [10, 10, 20, output, "parallel", 0, 0, 1, 5],
            [10, 10, 20, output, "parallel", 0, 0, 1, 2, "extra"],
            [10, 10, 20, output, "parallel", 0],
            [10, 10],
        ]
        for args in cases:
            with self.subTest(args=args):
                result = self.invoke(args)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())

    def test_missing_output_directory_reports_an_error(self):
        result = self.invoke(
            [3, 2, 10, self.directory / "missing" / "image.ppm", "parallel"]
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(result.stderr.strip() or result.stdout.strip())

    def test_help(self):
        result = self.invoke(["--help"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Usage:", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
