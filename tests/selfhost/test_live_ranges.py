#!/usr/bin/env python3
"""存在区间推导（v6 数据基础）——O1/O2 编译冒烟：区间表不破坏寄存器分配。

背景：compute_live_ranges 把 alloc_registers 的内联区间构建提取为独立表
（g_ir_live_ranges，每函数每 var 两条 i64：first_ref/last_ref，指令序），
alloc_registers 改读 live_first/live_last——行为必须与内联扫描一致。

覆盖路径：
- 默认 O1 build：pass_cse 路径（alloc_registers 在 O1 不运行，仍须正确）
- --opt-level 2 build：alloc_registers + pass_stack_share 路径（读新表）

fib(10)==55 为行为锚点（递归 + 分支密集，区间表错误会破坏寄存器指派）。
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

BASE = Path(__file__).resolve().parents[2]
COREC = BASE / "build" / "corec"


def build_and_run(source: str, extra_flags) -> int:
    with tempfile.NamedTemporaryFile("w", suffix=".cr", delete=False) as f:
        f.write(source)
        src = f.name
    out = src[:-3]
    try:
        b = subprocess.run([str(COREC), "build", src, "-o", out, "--static"] + extra_flags,
                           capture_output=True, text=True, cwd=BASE, timeout=120)
        if b.returncode != 0:
            print(f"  build stderr: {b.stderr.strip()[-500:]}")
            return 999
        r = subprocess.run([out], capture_output=True, text=True, timeout=10)
        return r.returncode
    finally:
        for p in (src, out, out + ".ccr"):
            try:
                os.unlink(p)
            except FileNotFoundError:
                pass


def main() -> int:
    if not COREC.exists():
        print("[FAIL] missing build/corec")
        return 1
    src = "fn fib(n:int)->int{if n<2{return n;}return fib(n-1)+fib(n-2);}\n" \
          "fn main()->int{return fib(10);}\n"
    passed = 0
    total = 2
    for name, flags in (("O1-default", []), ("O2", ["--opt-level", "2"])):
        rc = build_and_run(src, flags)
        ok = rc == 55
        print(f"[{'PASS' if ok else 'FAIL'}] {name} live-range smoke: rc={rc}")
        if ok:
            passed += 1
    print(f"{passed}/{total} passed")
    return 0 if passed == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
