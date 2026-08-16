#!/usr/bin/env python3
"""dex 类型核心测试（自举编译器 build/corec）—— 数值迁移 Task 3。

dex 是精确小数类型（float 并存期——float 关键字仍有效，移除是 Task 6）：
- `x : dex = 3.14` 合法（check exit 0）
- `fn f() -> dex { return 3.14; }` 合法
- `3.14` 字面量推断为 dex（`x := 3.14` 不报错；cir dump 字面量常量名为 dex）

断言点：
- dex 类型声明/返回通过类型检查（check exit 0）
- 字面量归属 dex：cir dump 中 main 的字面量 IR_CONST 变量名为 dex
  （float 时代为 "float"，见 ir_gen new_ir_var("float", TI_FLOAT)）
- 并存期回归守卫：float 关键字仍然有效（float 站点未迁移）
"""

import os
import re
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

BASE = Path(__file__).resolve().parents[2]
COREC = BASE / "build" / "corec"


def run_corec(args, source):
    """Write source to a temp file and run `corec <args> FILE.cr`.

    源文件首行注入唯一注释：改变 source hash，避免命中 .core/cache/cir/
    增量缓存（改源码后需 clean-cache 的地雷，见 CLAUDE.md）。
    """
    src = f"// dex-test-{uuid.uuid4()}\n" + source
    with tempfile.NamedTemporaryFile("w", suffix=".cr", delete=False) as f:
        f.write(src)
        path = f.name
    try:
        return subprocess.run(
            [str(COREC)] + args + [path],
            cwd=BASE,
            capture_output=True,
            text=True,
            timeout=120,
        )
    finally:
        os.unlink(path)


def test_dex_type_declares():
    # 1) 变量声明：x : dex = 3.14 → check exit 0
    src = (
        "fn main() -> int {\n"
        "    x : dex = 3.14;\n"
        "    return 1;\n"
        "}\n"
    )
    r = run_corec(["check"], src)
    if r.returncode != 0:
        print(f"[FAIL] dex var decl: exit={r.returncode}")
        print(r.stdout + r.stderr)
        return False
    print("[PASS] x : dex = 3.14 (check exit 0)")

    # 2) 函数返回类型：fn f() -> dex { return 3.14; } → check exit 0
    src2 = (
        "fn f() -> dex { return 3.14; }\n"
        "fn main() -> int { return 1; }\n"
    )
    r2 = run_corec(["check"], src2)
    if r2.returncode != 0:
        print(f"[FAIL] dex return type: exit={r2.returncode}")
        print(r2.stdout + r2.stderr)
        return False
    print("[PASS] fn f() -> dex { return 3.14; } (check exit 0)")

    # 3) 并存期守卫：float 关键字仍然有效（float 站点未迁移）→ check exit 0
    src3 = (
        "fn f() -> float { return 3.14; }\n"
        "fn main() -> int { return 1; }\n"
    )
    r3 = run_corec(["check"], src3)
    if r3.returncode != 0:
        print(f"[FAIL] float keyword (co-existence): exit={r3.returncode}")
        print(r3.stdout + r3.stderr)
        return False
    print("[PASS] fn f() -> float { return 3.14; } (co-existence, check exit 0)")
    return True


def test_dex_literal_type():
    # 1) 字面量推断：x := 3.14 不报错（3.14 推断为 dex——返回 1 走 int 路径）
    src = "fn main() -> int { x := 3.14; return 1; }\n"
    r = run_corec(["check"], src)
    if r.returncode != 0:
        print(f"[FAIL] literal infers dex: exit={r.returncode}")
        print(r.stdout + r.stderr)
        return False
    print("[PASS] x := 3.14 infers a real type (check exit 0)")

    # 2) 字面量归属 dex 的类型层证据：cir dump 中字面量 IR_CONST 变量名为 dex
    #    （float 时代为 "float"，ir_gen new_ir_var("float", TI_FLOAT)）
    rc = run_corec(["cir"], src)
    out = rc.stdout + rc.stderr
    if re.search(r"const\s+dex\s*=", out) is None:
        print("[FAIL] literal const should be 'dex' in cir dump")
        print(out)
        return False
    print("[PASS] cir dump shows literal const 'dex'")
    return True


def main():
    if not COREC.exists():
        print(f"[FAIL] missing native compiler: {COREC}")
        return 1
    results = [test_dex_type_declares(), test_dex_literal_type()]
    passed = sum(results)
    print(f"{passed}/{len(results)} passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
