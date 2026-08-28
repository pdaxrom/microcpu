#!/usr/bin/env python3
"""Reuse assembled SPI disk tests against a disposable read-only backing file."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import struct
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--testbench", default="build/disk.vvp")
    args = parser.parse_args()
    data = b"".join(struct.pack("<H", (sector << 8) ^ word ^ 0xA55A)
                    for sector in range(256) for word in range(256))
    with tempfile.TemporaryDirectory(prefix="microcpu-sd-image-") as directory:
        image = Path(directory) / "synthetic.dsk"
        image.write_bytes(data)
        image.chmod(0o444)

        def run(scenario):
            result = subprocess.run([args.vvp, args.testbench, f"+SCENARIO={scenario}",
                                     f"+SD_IMAGE={image}"], capture_output=True,
                                    text=True, timeout=300, check=False)
            if result.returncode or f"PASS: RK611/SD scenario {scenario};" not in result.stdout:
                raise AssertionError(result.stdout + result.stderr)
            if image.read_bytes() != data:
                raise AssertionError("SD simulation modified its source image")
            return result.stdout.strip()

        # Normal read/partial write, rejected write, partial DMA, bad cache fill.
        with ThreadPoolExecutor(max_workers=4) as pool:
            for output in pool.map(run, (0, 3, 7, 10)):
                print(output)
        for name, contents in (("empty.dsk", b""), ("short.dsk", b"x")):
            bad_image = Path(directory) / name
            bad_image.write_bytes(contents)
            result = subprocess.run([args.vvp, args.testbench, f"+SD_IMAGE={bad_image}"],
                                    capture_output=True, text=True, timeout=10, check=False)
            if result.returncode == 0 or "whole 512-byte sectors" not in result.stdout:
                raise AssertionError("Invalid image was not rejected: " + result.stdout)
    print("PASS: read-only SD image, RAM write overlay, restart isolation and invalid sizes")


if __name__ == "__main__":
    main()
