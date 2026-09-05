#!/usr/bin/env python3
"""存在区间推导 + 条目版本化（v6 数据基础）——O1/O2 编译冒烟：区间表不破坏寄存器分配。

背景：compute_live_ranges 把 alloc_registers 的内联区间构建提取为独立表
（g_ir_live_ranges，每函数每 var 两条 i64：first_ref/last_ref，指令序），
alloc_registers 改读 live_first/live_last——行为必须与内联扫描一致。

Task 2 追加：compute_entries 按定值点切分版本条目（变量 × 版本，24B/条）。
定值指令 = IR_ALLOC（局部槽初定值）与该变量为目标的每次 IR_STORE
（IR_STORE 形态 ρ(s1):=ρ(s2)——目标在 s1 不在 dest，见 ir-op-semantics.md）。
调试通道：`corec cir FILE.cr --dump-entries`（隐藏标志，与 opt 门控解耦——
cir 分支在任意 -O 下都先跑 compute_live_ranges（尾部 compute_entries）再出摘要）。

覆盖路径：
- 默认 O1 build：pass_cse 路径（alloc_registers 在 O1 不运行，仍须正确）
- --opt-level 2 build：alloc_registers + pass_stack_share 路径（读新表）
- cir --dump-entries：版本条目断言（多定值变量版本切割 / 参数无定值单条目）

fib(10)==55 为行为锚点（递归 + 分支密集，区间表错误会破坏寄存器指派）。

条目版本化断言注记：brief/计划示例 `x:=1;x=x+1;x=x+2` 预期 x 3 条目
（按「let 初始化只发射 IR_ALLOC」的 IR 模型估算）。实际 IR 中 `x := 1` 发射
IR_ALLOC(x) + IR_STORE(x←1) 两条定值（ir_gen.cr EXPR_LET 路径），故 x 定值点 =
ALLOC + 3×STORE = 4 个版本条目。规则照计划原文逐字实现（每次 IR_STORE/IR_ALLOC
定值切分一个版本），测试按实际 IR 断言 4 条目 + 版本区间结构不变量。
"""

import os
import re
import subprocess
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


def dump_entries(source: str) -> tuple:
    """cir --dump-entries 通道：返回 (rc, stdout)。不落盘（dump 分支先返回）。"""
    with tempfile.NamedTemporaryFile("w", suffix=".cr", delete=False) as f:
        f.write(source)
        src = f.name
    try:
        r = subprocess.run([str(COREC), "cir", src, "--dump-entries"],
                           capture_output=True, text=True, cwd=BASE, timeout=120)
        return r.returncode, r.stdout
    finally:
        try:
            os.unlink(src)
        except FileNotFoundError:
            pass


ENTRY_LINE = re.compile(
    r"^e (\d+) var (\d+) name=(\S+) v (\d+) def (-?\d+) kind=(\S+) "
    r"live (\d+)\.\.(\d+) home (-?\d+) flags (\d+)$")
HEADER_LINE = re.compile(r"^== entries func (\d+) \((.*)\): (\d+)$")


def parse_entry_blocks(out: str) -> dict:
    blocks = {}
    cur = None
    for raw in out.splitlines():
        ln = raw.strip()
        m = HEADER_LINE.match(ln)
        if m:
            blocks[m.group(2)] = []
            cur = blocks[m.group(2)]
            continue
        m = ENTRY_LINE.match(ln)
        if m and cur is not None:
            cur.append({
                "e": int(m.group(1)), "var": int(m.group(2)), "name": m.group(3),
                "v": int(m.group(4)), "def": int(m.group(5)), "kind": m.group(6),
                "ls": int(m.group(7)), "le": int(m.group(8)),
                "home": int(m.group(9)), "flags": int(m.group(10)),
            })
    return blocks


def check_versioned_entries() -> tuple:
    """Task 2：多定值变量版本切割断言。

    x := 1 在 IR 中 = IR_ALLOC + IR_STORE（let 初始化发射两条定值），
    再加 x=x+1 / x=x+2 两条 STORE → x 应有 4 个版本条目（1×ALLOC + 3×STORE），
    版本区间按 [def_j, min(def_{j+1}-1, last_ref)] 切割（全局指令序闭区间）：
    e_j.live_end == def_{j+1} - 1（j < 末版），末版 live_end = var 的 last_ref ≥ 其 def。
    """
    src = "fn identity(n:int)->int{return n;}\n" \
          "fn main()->int{x:=1;x=x+1;x=x+2;return x;}\n"
    rc, out = dump_entries(src)
    if rc != 0:
        return False, f"cir --dump-entries rc={rc}\n{out[-500:]}"
    blocks = parse_entry_blocks(out)
    if "main" not in blocks:
        return False, f"no 'main' entry block in dump:\n{out[-500:]}"
    ent = blocks["main"]

    multi = [x for x in ent if x["def"] >= 0]
    if len(multi) != 4:
        return False, f"main: expected 4 def'd entries for x (ALLOC+3 STORE), got {len(multi)}:\n{out}"
    if len({x["var"] for x in multi}) != 1:
        return False, f"main: def'd entries span multiple vars:\n{multi}"
    if [x["kind"] for x in multi] != ["ALLOC", "STORE", "STORE", "STORE"]:
        return False, f"main: def kinds != ALLOC,STORE,STORE,STORE:\n{multi}"
    if [x["v"] for x in multi] != [1, 2, 3, 4]:
        return False, f"main: version ordinals != 1..4:\n{multi}"
    defs = [x["def"] for x in multi]
    if any(defs[i] >= defs[i + 1] for i in range(3)):
        return False, f"main: def points not strictly increasing:\n{defs}"
    for x in multi:
        if x["ls"] != x["def"]:
            return False, f"main: version live_start != def ({x}):\n{multi}"
    for i in range(3):
        if multi[i]["le"] != defs[i + 1] - 1:
            return False, f"main: version {i+1} live_end != def[{i+1}]-1:\n{multi}"
    if multi[3]["le"] < multi[3]["def"]:
        return False, f"main: last version live_end < its def:\n{multi}"
    if not any(x["def"] == -1 for x in ent):
        return False, "main: expected >=1 no-def entry (temps/_arena), none found"
    if any(x["home"] != -1 or x["flags"] != 0 for x in ent):
        return False, f"main: entries must have home=-1 flags=0 (unassigned):\n{ent}"

    # 无定值但有引用（函数参数）：单条目 def=-1，区间 [first_ref,last_ref]
    if "identity" not in blocks or not blocks["identity"]:
        return False, f"identity: expected >=1 no-def entry:\n{out}"
    for x in blocks["identity"]:
        if x["def"] != -1 or x["kind"] != "-":
            return False, f"identity: params must be single def=-1 entries:\n{blocks['identity']}"
        if x["ls"] < 0 or x["ls"] > x["le"]:
            return False, f"identity: bad no-def live range:\n{x}"
    return True, "entries versioning OK"


def run_smoke() -> tuple:
    """Task 1 存量冒烟：fib(10)==55 at O1-default / O2。"""
    src = "fn fib(n:int)->int{if n<2{return n;}return fib(n-1)+fib(n-2);}\n" \
          "fn main()->int{return fib(10);}\n"
    passed = 0
    total = 2
    detail = []
    for name, flags in (("O1-default", []), ("O2", ["--opt-level", "2"])):
        rc = build_and_run(src, flags)
        ok = rc == 55
        print(f"[{'PASS' if ok else 'FAIL'}] {name} live-range smoke: rc={rc}")
        if ok:
            passed += 1
        else:
            detail.append(f"{name} rc={rc}")
    return passed == total, "; ".join(detail) if detail else ""


def main() -> int:
    if not COREC.exists():
        print("[FAIL] missing build/corec")
        return 1
    passed = 0
    total = 2
    ok, msg = run_smoke()
    if ok:
        passed += 1
    print(f"[{'PASS' if ok else 'FAIL'}] live-range smoke: {msg}")
    ok, msg = check_versioned_entries()
    if ok:
        passed += 1
    print(f"[{'PASS' if ok else 'FAIL'}] entries versioning: {msg}")
    print(f"{passed}/{total} passed")
    return 0 if passed == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
