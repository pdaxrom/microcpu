#!/usr/bin/env python3
"""Fail if development of ucode changes either preserved RTL/firmware profile."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = "d4dabf1"


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def main():
    files = ["rtl/cpu.v", "rtl/j11_microengine.v"]
    files += [name for name in git("ls-tree", "-r", "--name-only", REFERENCE,
                                  "ucode").decode().splitlines()
              if Path(name).parent == Path("ucode") and
              Path(name).suffix in (".asm", ".inc")]
    changed = [name for name in files
               if (ROOT / name).read_bytes() != git("show", f"{REFERENCE}:{name}")]
    if changed:
        raise SystemExit("Preserved profile changed: " + ", ".join(changed))
    print(f"PASS: {len(files)} original/preserved RTL and assembly files match {REFERENCE}")


if __name__ == "__main__":
    main()
