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


def dump_coexist(source: str) -> tuple:
    """cir --dump-coexist 通道：返回 (rc, stdout)。"""
    with tempfile.NamedTemporaryFile("w", suffix=".cr", delete=False) as f:
        f.write(source)
        src = f.name
    try:
        r = subprocess.run([str(COREC), "cir", src, "--dump-coexist"],
                           capture_output=True, text=True, cwd=BASE, timeout=120)
        return r.returncode, r.stdout + r.stderr
    finally:
        os.unlink(src)


COEXIST_LINE = re.compile(
    r"^== coexist func (\d+) \((\S+)\): ver_conf (\d+) home_conf (\d+)$",
    re.MULTILINE)


def check_coexistence() -> tuple:
    """Task 3：共存推导断言。

    (a) 版本冲突扫描 = 0（版本按定值点切割，同 var 跨版本必不交——数据自检）；
    (b) home 冲突 = 0（未分配态 home=-1 不参与，共存互斥判定输入雏形）；
    (c) 概念断言（Python 侧用 --dump-entries 区间数据）：a/b 两变量条目
        存在区间相交（共存），同一变量两版本区间不相交（不共存）。
    """
    src = "fn main()->int{a:=1;b:=2;return a+b;}\n"
    rc, out = dump_coexist(src)
    if rc != 0:
        return False, f"cir --dump-coexist rc={rc}\n{out[-500:]}"
    m = COEXIST_LINE.search(out)
    if not m:
        return False, f"no coexist line in dump:\n{out[-500:]}"
    vc, hc = int(m.group(3)), int(m.group(4))
    if vc != 0 or hc != 0:
        return False, f"coexist: ver_conf={vc} home_conf={hc}, expected 0/0:\n{out}"

    # (c) 区间相交概念断言（Python 侧）
    rc2, out2 = dump_entries(src)
    if rc2 != 0:
        return False, f"dump-entries rc={rc2}"
    blocks = parse_entry_blocks(out2)
    if "main" not in blocks:
        return False, "no main block"
    ent = blocks["main"]
    av = [x for x in ent if x["name"] == "a"]
    bv = [x for x in ent if x["name"] == "b"]
    if not av or not bv:
        return False, f"a/b entries missing:\n{out2}"
    # 取末版本（return 处活跃的是最后定值版——ALLOC 空版区间短暂不相交属正常；
    # a/b 在此程序各有 ALLOC+STORE 两版本）
    if len(av) < 2 or len(bv) < 2:
        return False, f"a/b should each have >=2 versions (ALLOC+STORE):\n{out2}"
    a0, b0 = av[-1], bv[-1]
    coexist = a0["ls"] <= b0["le"] and b0["ls"] <= a0["le"]
    if not coexist:
        return False, f"a/b should coexist, ranges {a0['ls']}..{a0['le']} vs {b0['ls']}..{b0['le']}"
    # a 两版本（ALLOC 空版 vs STORE 值版）区间不相交——同变量版本不共存
    if av[0]["ls"] <= av[1]["le"] and av[1]["ls"] <= av[0]["le"]:
        return False, f"a versions should not coexist: {av[0]['ls']}..{av[0]['le']} vs {av[1]['ls']}..{av[1]['le']}"
    return True, "coexistence OK"


def check_regalloc(source: str, extra_flags) -> tuple:
    """cir --check-regalloc 通道：O2 强制分配 + 判定自检，返回 (rc, stdout)。"""
    with tempfile.NamedTemporaryFile("w", suffix=".cr", delete=False) as f:
        f.write(source)
        src = f.name
    try:
        r = subprocess.run([str(COREC), "cir", src, "--check-regalloc"] + extra_flags,
                           capture_output=True, text=True, cwd=BASE, timeout=120)
        return r.returncode, r.stdout + r.stderr
    finally:
        try:
            os.unlink(src)
        except FileNotFoundError:
            pass


SUMMARY_LINE = re.compile(r"^regalloc-consistency: funcs (\d+) violations (\d+)$", re.MULTILINE)
VIOLATION_LINE = re.compile(r"^regalloc-consistency: func \d+ \(.+\): rule (\d+) violation", re.MULTILINE)
ASSIGN_LINE = re.compile(r"^regalloc-assign: (\d+) pairs$", re.MULTILINE)


def check_regalloc_consistency() -> tuple:
    """Task 5 绿路径 + CAG 真实化回归：O2 分配的**正确程序**自检静默通过
    （rc=0、无 violation 行）。

    CAG 前（2026-09-06 注记，opt.cr alloc 区头）：分配结果恒为空（rc=0 缺陷
    ——free 遍时机 + 循环末只收仍活跃 var → g_opt_meta 无 REG_ASSIGN 对），规则
    ①/② 在真实数据上平凡通过（无寄存器驻留条目）。CAG 挂账清项后分配真实化：
    本绿路径消费真实分配结果——寄存器组规则 ①/② 在真数据上必须仍绿（判定
    消费端首次吃到真数据；误报即红）。规则 ①/② 的实际触发证据 = 注入红路径
    （check_regalloc_violations / check_regalloc_read_gap_nonfunc0，注入现以
    改写真实分配输出为手段）；fib/6 变量绿程序按行为锚点保留。"""
    for name, src in (
        ("fib", "fn fib(n:int)->int{if n<2{return n;}return fib(n-1)+fib(n-2);}\n"
                "fn main()->int{return fib(10);}\n"),
        ("multi-var", "fn main()->int{a:=1;b:=2;c:=3;d:=4;e:=5;f:=6;"
                      "return a+b+c+d+e+f;}\n"),
    ):
        rc, out = check_regalloc(src, [])
        if rc != 0:
            return False, f"check-regalloc({name}) rc={rc}:\n{out[-500:]}"
        m = SUMMARY_LINE.search(out)
        if not m:
            return False, f"check-regalloc({name}): no summary line:\n{out[-500:]}"
        if int(m.group(2)) != 0:
            return False, f"check-regalloc({name}): violations != 0:\n{out[-500:]}"
        if VIOLATION_LINE.search(out):
            return False, f"check-regalloc({name}): violation lines on correct program:\n{out[-500:]}"
    return True, "regalloc consistency self-check OK"


def check_regalloc_real_use() -> tuple:
    """CAG 挂账清项（opt.cr alloc_registers rc=0 缺陷）：寄存器真实分配实证。

    --check-regalloc 在 O2 强制分配后打印看门狗行 regalloc-assign（g_opt_meta
    REG_ASSIGN 对总数）。修复前 rc 恒为 0（free 遍 `last_ref < ii` 复位 + reg_idx
    单调不复用 + 循环末只收集仍活跃 var → meta 恒空 → 后端全栈发射——正确但无
    寄存器加速）→ 本断言红；真实分配后 pairs > 0 → 绿。

    覆盖源 = 6 个共存 int var（压 5 callee-saved 上限）：分配真实发生（≥1 对）
    且必有栈驻留余数——驱逐/落 home（不分配 = 保留栈 home）路径共存验证。
    """
    src = "fn main()->int{a:=1;b:=2;c:=3;d:=4;e:=5;f:=6;return a+b+c+d+e+f;}\n"
    rc, out = check_regalloc(src, [])
    if rc != 0:
        return False, f"check-regalloc rc={rc}:\n{out[-500:]}"
    m = ASSIGN_LINE.search(out)
    if not m:
        return False, (f"regalloc-assign watchdog line missing in check-regalloc "
                       f"output:\n{out[-500:]}")
    n = int(m.group(1))
    if n <= 0:
        return False, (f"regalloc-assign: {n} pairs — 寄存器从未真实分配（rc=0 "
                       f"缺陷回退）：\n{out[-500:]}")
    if n < 5:
        return False, (f"regalloc-assign: {n} pairs < 5 — 6 共存 var 应吃满 "
                       f"5 callee-saved：\n{out[-500:]}")
    return True, f"regalloc real assignment OK ({n} pairs)"


LOOP_CARRY_SRC = (
    "fn main()->int{\n"
    "  i:=0;s:=0;\n"
    "  loop {\n"
    "    if i>=4 { break; }\n"
    "    i = i + 1;\n"
    "    d := 5;\n"
    "    s = s + d;\n"
    "  }\n"
    "  return s;\n"
    "}\n"
)


def check_regalloc_loop_carry() -> tuple:
    """CAG 上下文贪心——循环携带值语义锚（region 生命周期上下文）。

    i 的读点（cond）在文字序上先于其重定值（i=i+1）→ 每轮迭代末写入的值跨回边
    存活（cond 读的是上一轮 i 的值）。朴素 [first_ref, last_ref] 文字窗口序
    First Fit 会把 i 的寄存器（窗口止于其末引用 = 重定值点）与循环尾文字区间不
    交的 var（d := 5 的 ALLOC/STORE 在 i 末引用之后）共享 → d 的定值在回边前
    污染 i 的寄存器 → 下轮 cond 读到 5 → 提前 break（s=5）。上下文贪心把携带
    值（region 内首引用为读）窗口扩至整函数 → 不共享 → s = 4×5 = 20。

    断言 O2（真实分配）行为 == 20；O1（无分配路径基线）同断言。
    """
    for name, flags in (("O1-baseline", []), ("O2-regalloc", ["--opt-level", "2"])):
        rc = build_and_run(LOOP_CARRY_SRC, flags)
        ok = rc == 20
        print(f"[{'PASS' if ok else 'FAIL'}] loop-carry {name}: rc={rc}")
        if not ok:
            return False, f"loop-carry {name} rc={rc}, expected 20"
    return True, "loop-carried register semantics OK"


def check_regalloc_violations() -> tuple:
    """Task 5 红路径：注入冲突条目 → verify 返回违反（rc=1 + rule N 诊断行）。
    注入经测试钩子（cir 隐藏 debug 标志——真实构建路径永不注入）：
    - --inject-home-conflict: 两条共存不同 var 条目 home 置同槽 → 规则 1（home 组）
    - --inject-reg-conflict : 未分配 var f 伪造 meta 对 (f, e 的寄存器) → 规则 1（寄存器组）
    - --inject-read-gap     : 寄存器驻留 var 末版区间截断到定值点 → 规则 2（读点无版本）
    O2 正确程序（无注入）rc=0 已在 check_regalloc_consistency 断言——同一二进制
    注入后 rc=1 即证明 verify 真消费了分配/条目数据而非恒真。"""
    src = "fn main()->int{a:=1;b:=2;c:=3;d:=4;e:=5;f:=6;return a+b+c+d+e+f;}\n"
    for flag, rule in (("--inject-home-conflict", "1"),
                       ("--inject-reg-conflict", "1"),
                       ("--inject-read-gap", "2")):
        rc, out = check_regalloc(src, [flag])
        if rc != 1:
            return False, f"check-regalloc +{flag}: rc={rc}, expected 1:\n{out[-500:]}"
        m = SUMMARY_LINE.search(out)
        if not m or int(m.group(2)) == 0:
            return False, f"check-regalloc +{flag}: summary missing or 0 violations:\n{out[-500:]}"
        v = VIOLATION_LINE.search(out)
        if not v or v.group(1) != rule:
            return False, f"check-regalloc +{flag}: no rule {rule} violation line:\n{out[-500:]}"
    return True, "regalloc violations detected (rules 1/1/2)"


def check_regalloc_read_gap_nonfunc0() -> tuple:
    """F1 回归（评审发现）：规则 ② 注入目标 = 非 func 0 函数。

    rl_rule2_func 曾以局部扫描下标 ii 对照条目表全局坐标（ent_def/ent_live_end
    存 ist+局部），非 func 0 函数（ist > 0）上规则 ② 失明（只漏报不误报）——
    func 0 上 ii == inst 掩盖缺陷。本用例把 --inject-read-gap 的注入目标推到
    func 9（sum6）：前导 noop 函数撑大 ist（实测 sum6 ist=49 > ic≈26，读点局部
    下标永不越过全局 def）——旧实现漏报 rc=0（红），修复（三处比较改用
    inst := ist + ii）后 rc=1 + func 9 (sum6) 规则 ② 诊断行（绿）。"""
    src = "fn main()->int{return n0(1,2);}\n" \
          "fn n0(a:int,b:int)->int{return a+b;}\n" \
          "fn n1(a:int,b:int)->int{return a+b;}\n" \
          "fn n2(a:int,b:int)->int{return a+b;}\n" \
          "fn n3(a:int,b:int)->int{return a+b;}\n" \
          "fn n4(a:int,b:int)->int{return a+b;}\n" \
          "fn n5(a:int,b:int)->int{return a+b;}\n" \
          "fn n6(a:int,b:int)->int{return a+b;}\n" \
          "fn n7(a:int,b:int)->int{return a+b;}\n" \
          "fn sum6()->int{a:=1;b:=2;c:=3;d:=4;e:=5;f:=6;return a+b+c+d+e+f;}\n"
    rc, out = check_regalloc(src, ["--inject-read-gap"])
    if rc != 1:
        return False, f"check-regalloc +--inject-read-gap (non-func0): rc={rc}, expected 1:\n{out[-500:]}"
    m = SUMMARY_LINE.search(out)
    if not m or int(m.group(2)) == 0:
        return False, f"check-regalloc +--inject-read-gap (non-func0): summary missing or 0 violations:\n{out[-500:]}"
    v = re.search(r"^regalloc-consistency: func (\d+) \((\S+)\): rule (\d+) violation",
                  out, re.MULTILINE)
    if not v:
        return False, f"check-regalloc +--inject-read-gap (non-func0): no violation line:\n{out[-500:]}"
    if v.group(3) != "2" or v.group(2) != "sum6" or int(v.group(1)) == 0:
        return False, (f"check-regalloc +--inject-read-gap (non-func0): violation not on "
                       f"non-func-0 rule 2 (got func {v.group(1)} ({v.group(2)}) rule "
                       f"{v.group(3)}):\n{out[-500:]}")
    return True, "read-gap detected on non-func-0 func (rule 2)"


def main() -> int:
    if not COREC.exists():
        print("[FAIL] missing build/corec")
        return 1
    passed = 0
    total = 8
    ok, msg = run_smoke()
    if ok:
        passed += 1
    print(f"[{'PASS' if ok else 'FAIL'}] live-range smoke: {msg}")
    ok, msg = check_versioned_entries()
    if ok:
        passed += 1
    print(f"[{'PASS' if ok else 'FAIL'}] entries versioning: {msg}")
    ok, msg = check_coexistence()
    if ok:
        passed += 1
    print(f"[{'PASS' if ok else 'FAIL'}] coexistence: {msg}")
    ok, msg = check_regalloc_consistency()
    if ok:
        passed += 1
    print(f"[{'PASS' if ok else 'FAIL'}] regalloc consistency: {msg}")
    ok, msg = check_regalloc_real_use()
    if ok:
        passed += 1
    print(f"[{'PASS' if ok else 'FAIL'}] regalloc real use: {msg}")
    ok, msg = check_regalloc_loop_carry()
    if ok:
        passed += 1
    print(f"[{'PASS' if ok else 'FAIL'}] regalloc loop carry: {msg}")
    ok, msg = check_regalloc_violations()
    if ok:
        passed += 1
    print(f"[{'PASS' if ok else 'FAIL'}] regalloc violations: {msg}")
    ok, msg = check_regalloc_read_gap_nonfunc0()
    if ok:
        passed += 1
    print(f"[{'PASS' if ok else 'FAIL'}] regalloc read-gap non-func0: {msg}")
    print(f"{passed}/{total} passed")
    return 0 if passed == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
