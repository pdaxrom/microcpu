#!/usr/bin/env python3
"""Boot a user-owned raw RT-11 disk through the complete SPI/UART Verilog TB.

The card model opens the image rb and stores changes in a volatile RAM overlay.
No RT-11 files or disk images are distributed with the test. Hash the input
before AND after the run (including failure), and require actual console output,
not just the testbench reaching $finish.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--binary", type=Path, help="compiled Verilator testbench")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--testbench", default="build/rt11.vvp")
    parser.add_argument("--work-dir", type=Path, default=Path("build/rt11"))
    parser.add_argument("--timeout", type=float, default=3600)
    parser.add_argument("--max-cycles", type=int, default=2000000000)
    parser.add_argument("--trace", action="store_true")
    parser.add_argument("--bootstrap-only", action="store_true")
    args = parser.parse_args()
    if not 0 < args.max_cycles <= 2000000000 or args.timeout <= 0:
        parser.error("max-cycles must be 1..2000000000 and timeout must be positive")
    image = args.image.resolve(strict=True)
    if not image.is_file() or image.stat().st_size == 0 or image.stat().st_size % 512:
        parser.error("image must be a nonempty file of whole 512-byte sectors")
    work = args.work_dir.resolve()
    # Do not let output selection overwrite the input, even with unusual names.
    outputs = [work / name for name in ("console.log", "simulation.log", "trace.log", "result.json")]
    if any(p.resolve() == image or (p.exists() and p.samefile(image)) for p in outputs):
        parser.error("input image collides with a test output")
    work.mkdir(parents=True, exist_ok=True)
    before = sha256(image)
    command = ([str(args.binary.resolve())] if args.binary else
               [args.vvp, "-i", args.testbench])
    command += [f"+SD_IMAGE={image}", f"+CONSOLE={work / 'console.log'}",
                f"+MAX_CYCLES={args.max_cycles}"]
    if args.trace:
        command.append(f"+TRACE={work / 'trace.log'}")
    if args.bootstrap_only:
        command.append("+BOOTSTRAP_ONLY")
    started = time.monotonic()
    failure = None
    code = None
    try:
        with (work / "simulation.log").open("w") as log:
            code = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                  timeout=args.timeout, check=False).returncode
    except (subprocess.TimeoutExpired, OSError) as exc:
        failure = str(exc)
    after = sha256(image)
    console = (work / "console.log").read_text(errors="replace") if (work / "console.log").exists() else ""
    simulation = (work / "simulation.log").read_text(errors="replace")
    checks = {
        "simulator_completed": code == 0 and "RT11 simulation complete:" in simulation,
        "image_unchanged": before == after,
        "rt11fb_banner": "RT-11FB (S) V05.03" in console,
        "show_configuration": "Booted from DM0:RT11FB" in console,
        "processor_identification": "PDP 11/73A Processor" in console,
        "no_mmu_memory": "56KB of memory" in console,
        "directory": re.search(r"RT11FB\s*\.SYS\s+103P?(?:\s|$)", console) is not None,
        "no_guest_errors": re.search(r"\?(?:BOOT|KMON|MON|PIP|DIR|DUP|RESORC)-[FE]-", console) is None,
    }
    if args.bootstrap_only:
        checks = {"bootstrap": code == 0 and "PASS: RT11 bootstrap," in simulation,
                  "image_unchanged": before == after}
    result = {"image": str(image), "sha256_before": before, "sha256_after": after,
              "command": command, "seconds": round(time.monotonic() - started, 3),
              "exit_code": code, "failure": failure, "checks": checks}
    (work / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(console)
    print(f"Logs: {work}")
    if failure or not all(checks.values()):
        print("FAIL:", failure or ", ".join(key for key, ok in checks.items() if not ok))
        return 1
    description = "two-sector bootstrap" if args.bootstrap_only else "boot, SHOW CONFIGURATION, directory"
    print(f"PASS: RT-11 {description}; source image unchanged ({before})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
