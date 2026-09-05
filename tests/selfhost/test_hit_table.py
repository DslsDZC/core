#!/usr/bin/env python3
"""HIT 表驱动发射测试（M1 Task 2）——corearch --table 逐字节对照 + 运行正确性。

M1 Task 2 = 表驱动编码器框架（emit_instr_tabled + hit_map_ir_op）：
- 映射面：IR_BINARY(OP_SUB, int) → sub 事件（直通）；其余 op 落旧路径（混合模式）
- 判据 1（逐字节对照）：同一 .ccr 经旧路径与 --table 路径产出的 ELF 逐字节一致
  ——表覆盖形态（sub）与混合形态（sub 走表、add/const/load 落旧）都对照
- 判据 2（运行正确性）：表模式 ELF 运行 exit code = 期望值（与旧路径一致）
- 判据 3：表模式真实经表发射（stdout "hit table: N tabled instrs emitted"，N ≥ 1）
- 表加载失败路径 exit 1；hit.cr 独立编译干净（corec check）

需先重建自举编译器：nice -n 19 python3 build_selfhost_native.py
"""

import subprocess
import sys
import tempfile
from pathlib import Path

BASE = Path(__file__).resolve().parents[2]
COREC = BASE / "build" / "corec"
COREARCH = BASE / "build" / "corearch"
TABLE = BASE / "src" / "arch" / "hit" / "core-x86.toml"
HIT_SRC = BASE / "src" / "arch" / "hit" / "hit.cr"
OPT = "1"  # 与 corec build 默认同（corec/main.cr: g_opt_level 默认 1）

# 载体 1：纯 sub（IR 层 const + sub + return；sub 走表，const/load/return 落旧路径）
SUB_SRC = "fn main() -> int {\n    x := 5;\n    y := 3;\n    return x - y;\n}\n"
SUB_RC = 2  # 5 - 3

# 载体 2：两处 sub + 一处 add（add 未映射 → 混合模式落旧路径）
MIXED_SRC = """fn main() -> int {
    a := 7;
    b := 3;
    c := 10;
    d := 4;
    return (a - b) + (c - d);
}
"""
MIXED_RC = 10  # (7-3) + (10-4)


def run_bin(binary, args):
    return subprocess.run(
        [str(binary)] + args,
        cwd=BASE,
        capture_output=True,
        text=True,
        timeout=300,
    )


def compile_ccr(tmp: Path, name: str, src: str):
    """corec ccr：.cr → .ccr（仅前端，不落 corearch）。"""
    src_p = tmp / f"{name}.cr"
    src_p.write_text(src)
    ccr_p = tmp / f"{name}.ccr"
    r = run_bin(COREC, ["ccr", str(src_p), "-o", str(ccr_p), "--opt-level", OPT])
    if r.returncode != 0:
        raise RuntimeError(f"corec ccr failed: {r.stdout + r.stderr}")
    if not ccr_p.exists():
        raise RuntimeError(f"corec ccr produced no .ccr: {r.stdout + r.stderr}")
    return ccr_p


def emit_bin(ccr: Path, out: Path, table: bool):
    args = [str(ccr), "--elf", "--opt-level", OPT, "-o", str(out)]
    if table:
        args += ["--table", str(TABLE)]
    r = run_bin(COREARCH, args)
    if r.returncode != 0:
        raise RuntimeError(f"corearch failed ({'table' if table else 'old'}): {r.stdout + r.stderr}")
    if not out.exists():
        raise RuntimeError(f"corearch produced no output: {r.stdout + r.stderr}")
    return r


def build_both(tmp: Path, name: str, src: str):
    """同一 .ccr → 旧路径 + --table 路径两 ELF；返回 (old_bytes, tab_bytes, tab_run_stdout)。"""
    ccr = compile_ccr(tmp, name, src)
    old_out = tmp / f"{name}_old"
    tab_out = tmp / f"{name}_tab"
    old_r = emit_bin(ccr, old_out, table=False)
    tab_r = emit_bin(ccr, tab_out, table=True)
    return old_out.read_bytes(), tab_out.read_bytes(), old_r.stdout + old_r.stderr, tab_r.stdout + tab_r.stderr


def run_elf(bin_path: Path):
    r = subprocess.run([str(bin_path)], capture_output=True, text=True, timeout=60)
    return r.returncode


def test_byte_identical(tmp: Path, name: str, src: str, expected_rc: int, need_tabled: bool) -> bool:
    """逐字节对照 + 运行 exit code 断言（表模式必须真实经表发射）。"""
    try:
        old_b, tab_b, old_out, tab_out = build_both(tmp, name, src)
    except RuntimeError as e:
        print(f"[FAIL] {name}: {e}")
        return False
    if old_b != tab_b:
        n = min(len(old_b), len(tab_b))
        diff_at = next((i for i in range(n) if old_b[i] != tab_b[i]), n)
        print(f"[FAIL] {name}: old vs --table ELF differ at byte {diff_at} "
              f"(len {len(old_b)} vs {len(tab_b)})")
        return False
    print(f"[PASS] {name}: --table ELF byte-identical to old path ({len(tab_b)} bytes)")
    if "hit table loaded: 4 events" not in tab_out:
        print(f"[FAIL] {name}: missing 'hit table loaded: 4 events' in --table output")
        print(tab_out)
        return False
    if need_tabled:
        # 表模式必须真实发射过表映射指令（防表路径空转假绿）
        marker = " tabled instrs emitted"
        m = tab_out.find(marker)
        if m < 0:
            print(f"[FAIL] {name}: missing 'tabled instrs emitted' summary in --table output")
            print(tab_out)
            return False
        cnt_txt = tab_out[:m].rsplit("hit table: ", 1)[-1].strip()
        if not cnt_txt.isdigit() or int(cnt_txt) < 1:
            print(f"[FAIL] {name}: tabled instr count invalid: '{cnt_txt}'")
            print(tab_out)
            return False
    old_rc = run_elf(tmp / f"{name}_old")
    tab_rc = run_elf(tmp / f"{name}_tab")
    if old_rc != expected_rc or tab_rc != expected_rc:
        print(f"[FAIL] {name}: run exit codes old={old_rc} table={tab_rc} expected={expected_rc}")
        return False
    print(f"[PASS] {name}: old & --table ELF both exit {expected_rc}")
    return True


def test_table_load_missing_file(tmp: Path) -> bool:
    """表文件缺 → load 失败即退（exit 1），即使给了有效 .ccr。"""
    ccr = compile_ccr(tmp, "missing_tbl", SUB_SRC)
    r = run_bin(COREARCH, [str(ccr), "--elf", "--table", str(tmp / "no" / "such" / "table.toml")])
    if r.returncode == 0:
        print("[FAIL] corearch --table <missing> should exit 1")
        print(r.stdout + r.stderr)
        return False
    print("[PASS] corearch --table <missing> -> exit != 0")
    return True


def test_table_bad_opcode_range(tmp: Path) -> bool:
    """评审项：opcode >255 不得静默截断——表数据值域校验拒绝（exit 1）。"""
    ccr = compile_ccr(tmp, "bad_opcode_tbl", SUB_SRC)
    bad = tmp / "bad_opcode.toml"
    content = TABLE.read_text().replace("[0x4D, 0x29]", "[0x4D, 300]")
    bad.write_text(content)
    r = run_bin(COREARCH, [str(ccr), "--elf", "--table", str(bad)])
    if r.returncode == 0:
        print("[FAIL] corearch --table <opcode >255> should exit 1 (no silent truncation)")
        print(r.stdout + r.stderr)
        return False
    if "opcode byte >255" not in (r.stdout + r.stderr):
        print("[FAIL] expected 'opcode byte >255' error message")
        print(r.stdout + r.stderr)
        return False
    print("[PASS] corearch --table <opcode byte >255> -> exit 1 with error")
    return True


def test_hit_cr_checks_clean() -> bool:
    if not COREC.exists():
        print(f"[FAIL] missing build/corec: {COREC}")
        return False
    if not HIT_SRC.exists():
        print(f"[FAIL] missing hit.cr: {HIT_SRC}")
        return False
    r = run_bin(COREC, ["check", str(HIT_SRC)])
    if r.returncode != 0:
        print(f"[FAIL] corec check hit.cr exit={r.returncode}")
        print(r.stdout + r.stderr)
        return False
    print("[PASS] corec check src/arch/hit/hit.cr -> exit 0 (hit.cr 编译干净)")
    return True


def main():
    if not COREC.exists() or not COREARCH.exists():
        print("[FAIL] missing build/corec or build/corearch (run build_selfhost_native.py first)")
        return 1
    with tempfile.TemporaryDirectory(prefix="hit_t2_") as td:
        tmp = Path(td)
        results = [
            test_byte_identical(tmp, "sub", SUB_SRC, SUB_RC, need_tabled=True),
            test_byte_identical(tmp, "mixed", MIXED_SRC, MIXED_RC, need_tabled=True),
            test_table_load_missing_file(tmp),
            test_table_bad_opcode_range(tmp),
            test_hit_cr_checks_clean(),
        ]
    passed = sum(results)
    print(f"{passed}/{len(results)} passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
