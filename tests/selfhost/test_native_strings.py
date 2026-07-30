#!/usr/bin/env python3
"""Native ELF regression tests for hidden string length headers."""

import os
import shutil
import subprocess
from pathlib import Path


BASE = Path(__file__).resolve().parents[2]
BUILD = BASE / "build"
COREC = BUILD / "corec"
TEST_BUILD = BUILD / "test_native_strings"
SOURCE = TEST_BUILD / "native_string_lengths.cr"
BINARY = TEST_BUILD / "native_string_lengths"


def main() -> int:
    if not COREC.exists():
        print("build/corec is missing; run `python3 build_selfhost_native.py` first")
        return 1

    shutil.rmtree(TEST_BUILD, ignore_errors=True)
    TEST_BUILD.mkdir(parents=True)
    (TEST_BUILD / "src").symlink_to(BASE / "src", target_is_directory=True)
    SOURCE.write_text(
        """\
import fmt

struct Point { x: int, y: int }

fn main() -> int {
    if str_len("hello") != 5 { return 1; }
    fields := @fields(Point);
    if str_len(fields) != 3 { return 2; }
    return 0;
}
""",
        encoding="utf-8",
    )
    try:
        built = subprocess.run(
            [
                "nice",
                "-n",
                "19",
                str(COREC),
                "build",
                str(SOURCE),
                "-o",
                str(BINARY),
                "--static",
                "-O",
                "0",
            ],
            cwd=TEST_BUILD,
            capture_output=True,
            text=True,
            timeout=180,
        )
        if built.returncode != 0:
            print(f"[FAIL] native string build exited {built.returncode}")
            print(built.stdout)
            print(built.stderr)
            return 1
        os.chmod(BINARY, 0o755)
        result = subprocess.run([str(BINARY)], cwd=TEST_BUILD, timeout=30)
        if result.returncode != 0:
            print(
                f"[FAIL] native string length case returned {result.returncode}"
            )
            return 1
        print("[PASS] literal and @fields string lengths use valid ELF headers")
        return 0
    finally:
        shutil.rmtree(TEST_BUILD, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
