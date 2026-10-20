"""Compare native CPU modes using interleaved runs and pixel-identical output."""

import argparse
import hashlib
import os
import re
import statistics
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def positive(text):
    value = int(text)
    if value < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return value


def sample(mode, threads, output, args):
    result = subprocess.run(
        [
            str(ROOT / "build" / "mandelbrot"),
            "--threads",
            str(threads),
            str(args.width),
            str(args.height),
            str(args.iterations),
            str(output),
            mode,
            str(args.center_x),
            str(args.center_y),
            str(args.span),
            str(args.samples),
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=900,
    )
    match = re.search(r"Render time: (\d+) ms", result.stdout)
    if match is None:
        raise RuntimeError(f"Missing render timing: {result.stdout}")
    try:
        return int(match[1]), hashlib.sha256(output.read_bytes()).digest()
    except (ValueError, OSError) as error:
        raise RuntimeError("Could not read the render timing/image") from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--width", type=positive, default=960)
    parser.add_argument("--height", type=positive, default=640)
    parser.add_argument("--iterations", type=positive, default=300)
    parser.add_argument("--threads", type=positive, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--repeat", type=positive, default=5)
    parser.add_argument("--samples", type=positive, default=1)
    parser.add_argument("--center-x", type=float, default=-0.5)
    parser.add_argument("--center-y", type=float, default=0.0)
    parser.add_argument("--span", type=float, default=3.2)
    args = parser.parse_args()
    if args.samples > 4:
        parser.error("samples must be <= 4 (16 orbits/pixel)")
    if args.width > 8192 or args.height > 8192 or args.width * args.height > 16777216:
        parser.error("dimensions must be <= 8192 each and <= 16777216 pixels total")
    if args.iterations > 10000:
        parser.error("iterations must be <= 10000")
    modes = [("sequential", 1), ("parallel", args.threads)]
    times = {"sequential": [], "parallel": []}
    reference = None
    with tempfile.TemporaryDirectory(prefix="bend-bench-") as directory:
        output = Path(directory) / "frame.ppm"
        # One unmeasured warm-up per mode, then alternate execution order.
        for turn in range(args.repeat + 1):
            order = modes if turn % 2 == 0 else list(reversed(modes))
            for mode, threads in order:
                elapsed, digest = sample(mode, threads, output, args)
                if reference is None:
                    reference = digest
                if digest != reference:
                    raise RuntimeError("Image mismatch: refusing to compare timings")
                if turn > 0:
                    times[mode].append(elapsed)
    print(
        f"{args.width} x {args.height}, {args.iterations} iterations, "
        f"{args.samples**2} samples/pixel, {args.repeat} runs/mode"
    )
    print("Render + pixel-buffer allocation only; excludes process start and file IO.")
    print("Millisecond resolution; fresh process per run, not a persistent renderer.")
    for mode, threads in modes:
        print(
            f"{mode:10s} ({threads} workers): {statistics.median(times[mode]):g} ms median; {times[mode]}"
        )
    parallel = statistics.median(times["parallel"])
    if parallel > 0:
        print(f"Speedup: {statistics.median(times['sequential']) / parallel:.2f}x")
    else:
        print("Increase the image size or iteration limit for measurable timings.")
    print("All output images are byte-identical.")


if __name__ == "__main__":
    main()
