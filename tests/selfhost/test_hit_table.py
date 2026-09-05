#!/usr/bin/env python3
"""HIT 表解析测试（M1 Task 1）——core-x86.toml 最小核 4 事件加载。

通过 corearch `--table <path>` 通道驱动（本任务即加：load 成功打印
"hit table loaded: N events" 并 exit 0；失败 exit 1）。Task 2 接发射后
本测试将扩展为表驱动输出 vs 硬编码路径逐字节对照。

断言点：
- `corearch --table src/arch/hit/core-x86.toml` → exit 0，stdout 含
  "hit table loaded: 4 events"（4 = sub/nand/load/store 最小核契约）
- `corearch --table <不存在路径>` → exit 1（文件缺 → load 失败路径）
- `corec check src/arch/hit/hit.cr` → exit 0（hit.cr 独立编译干净，
  含 toml 解析扩展不破既有管线）

需先重建自举编译器：nice -n 19 python3 build_selfhost_native.py
"""

import subprocess
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parents[2]
COREC = BASE / "build" / "corec"
COREARCH = BASE / "build" / "corearch"
TABLE = BASE / "src" / "arch" / "hit" / "core-x86.toml"
HIT_SRC = BASE / "src" / "arch" / "hit" / "hit.cr"


def run_bin(binary, args):
    return subprocess.run(
        [str(binary)] + args,
        cwd=BASE,
        capture_output=True,
        text=True,
        timeout=180,
    )


def test_table_load_ok():
    if not COREARCH.exists():
        print(f"[FAIL] missing build/corearch: {COREARCH}")
        return False
    if not TABLE.exists():
        print(f"[FAIL] missing HIT table file: {TABLE}")
        return False
    r = run_bin(COREARCH, ["--table", str(TABLE.relative_to(BASE))])
    out = r.stdout + r.stderr
    if r.returncode != 0:
        print(f"[FAIL] corearch --table exit={r.returncode}")
        print(out)
        return False
    if "hit table loaded: 4 events" not in out:
        print(f"[FAIL] expected 'hit table loaded: 4 events' in output")
        print(out)
        return False
    print("[PASS] corearch --table core-x86.toml -> exit 0, 'hit table loaded: 4 events'")
    return True


def test_table_load_missing_file():
    r = run_bin(COREARCH, ["--table", "no/such/table.toml"])
    if r.returncode == 0:
        print("[FAIL] corearch --table <missing> should exit 1")
        print(r.stdout + r.stderr)
        return False
    print("[PASS] corearch --table <missing> -> exit != 0")
    return True


def test_hit_cr_checks_clean():
    if not COREC.exists():
        print(f"[FAIL] missing build/corec: {COREC}")
        return False
    if not HIT_SRC.exists():
        print(f"[FAIL] missing hit.cr: {HIT_SRC}")
        return False
    r = run_bin(COREC, ["check", str(HIT_SRC.relative_to(BASE))])
    out = r.stdout + r.stderr
    if r.returncode != 0:
        print(f"[FAIL] corec check hit.cr exit={r.returncode}")
        print(out)
        return False
    print("[PASS] corec check src/arch/hit/hit.cr -> exit 0 (hit.cr 编译干净)")
    return True


def main():
    results = [test_table_load_ok(), test_table_load_missing_file(), test_hit_cr_checks_clean()]
    passed = sum(results)
    print(f"{passed}/{len(results)} passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
