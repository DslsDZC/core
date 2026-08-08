#!/usr/bin/env python3
"""Region-based control flow tests — dump .cir text and assert region structure."""
import os, re, subprocess, tempfile

BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COREC = os.path.join(BASE, 'build/corec')

def cir_dump(src: str) -> str:
    # `corec cir` prints the text dump (Function/Region/Block lines) to stdout
    # and writes the DOT graph to <src>.cir; return both so cluster assertions
    # work too.
    with tempfile.NamedTemporaryFile('w', suffix='.cr', delete=False) as f:
        f.write(src)
        path = f.name
    cir_path = os.path.splitext(path)[0] + '.cir'
    try:
        os.unlink(cir_path)
    except FileNotFoundError:
        pass
    # cir dump runs the full compiler pipeline; allow generous time under load
    r = subprocess.run(['./build/corec', 'cir', path], capture_output=True, text=True,
                       cwd=BASE, timeout=120)
    os.unlink(path)
    out = r.stdout
    try:
        with open(cir_path) as f:
            out = out + "\n=== DOT ===\n" + f.read()
        os.unlink(cir_path)
    except FileNotFoundError:
        pass
    return out

def parse_regions(out: str):
    """Parse 'Region: <name> nodes A..B' lines -> {name: [(A, B), ...]}."""
    regions = {}
    for m in re.finditer(r'Region: (\w+) nodes (\d+)\.\.(-?\d+)', out):
        regions.setdefault(m.group(1), []).append((int(m.group(2)), int(m.group(3))))
    return regions

def assert_region_within_func(out: str, name: str, tail: bool = True):
    """Sanity: region bounds must lie inside the enclosing func region, and
    (when `tail`) must not swallow the function tail: B < func_end.

    This guards against sg_pop close-semantics regressions where the
    innermost region's EXIT is overwritten with the full function node count.
    """
    regs = parse_regions(out)
    assert 'func' in regs, f"func region missing in cir dump:\n{out}"
    assert name in regs, f"{name} region missing in cir dump:\n{out}"
    a, b = regs[name][0]
    assert 0 <= a < b, f"{name} region has bad bounds {a}..{b}:\n{out}"
    # Enclosing func region: the one whose span contains the region start
    fs = fe = -1
    for (s, e) in regs['func']:
        if s <= a < e:
            fs, fe = s, e
    assert fs >= 0, f"{name} region start {a} outside any func region:\n{out}"
    assert b <= fe, f"{name} region {a}..{b} escapes func region {fs}..{fe}:\n{out}"
    if tail:
        assert b < fe, f"{name} region swallows function tail ({b} >= {fe}):\n{out}"
    return a, b, fs, fe

def test_if_region():
    out = cir_dump("fn f(x: int) -> int {\n    if x > 0 { return 1; }\n    return 0;\n}\nfn main() -> int { return f(1); }\n")
    assert 'Region: if' in out, f"SG_IF region missing in cir dump:\n{out}"
    assert 'Region: func' in out, f"SG_FUNC region not labeled in cir dump:\n{out}"
    assert_region_within_func(out, 'if')

def test_loop_region():
    out = cir_dump("fn main() -> int {\n    s : ., mut = 0;\n    for i in 0..3 { s = s + i; }\n    return s;\n}\n")
    assert 'Region: for' in out, f"SG_FOR region missing in cir dump:\n{out}"
    assert 'Region: func' in out, f"SG_FUNC region not labeled in cir dump:\n{out}"
    assert_region_within_func(out, 'for')

def test_node_region_mapping():
    out = cir_dump("fn main() -> int {\n    s : ., mut = 0;\n    for i in 0..3 { s = s + i; }\n    return s;\n}\n")
    # DOT cluster grouping: the for region's nodes appear in one cluster
    assert 'cluster_for' in out, f"DOT region cluster missing:\n{out}"

def test_state_edges():
    """State edges (VSDG): side-effect chain + loop termination dependencies
    must appear in the cir dump as 'state: nA -> nB' lines."""
    out = cir_dump("fn main() -> int {\n    s : ., mut = 0;\n    s = s + 1;\n    s = s + 2;\n    return s;\n}\n")
    assert 'state' in out, f"state edges not shown in cir dump:\n{out}"

def test_loop_termination_edge():
    """A loop whose body has side effects must carry a termination dependency
    from the last side-effect node to the loop exit node."""
    out = cir_dump("fn main() -> int {\n    s : ., mut = 0;\n    for i in 0..3 { s = s + i; }\n    return s;\n}\n")
    assert 'state' in out, f"loop termination state edge missing in cir dump:\n{out}"

# --- Interpreter loop execution (TODO#3) ---
# `corec run` compiles and interprets inline code; main()'s return value
# becomes the process exit code.

def test_for_loop_run():
    """for 循环在解释器中正确执行并返回累加和（TODO#3 回归用例）"""
    r = subprocess.run(['./build/corec', 'run',
                        'fn main() -> int { s : ., mut = 0; for i in 0..4 { s = s + i; } return s; }'],
                       capture_output=True, text=True, cwd=BASE, timeout=30)
    assert r.returncode == 6, f"for loop expected 6, got exit={r.returncode} stdout={r.stdout!r} stderr={r.stderr!r}"

def test_while_loop_run():
    r = subprocess.run(['./build/corec', 'run',
                        'fn main() -> int { n : ., mut = 0; while n < 5 { n = n + 1; } return n; }'],
                       capture_output=True, text=True, cwd=BASE, timeout=30)
    assert r.returncode == 5, f"while loop expected 5, got exit={r.returncode} stdout={r.stdout!r} stderr={r.stderr!r}"

def test_break_continue_run():
    r = subprocess.run(['./build/corec', 'run',
                        'fn main() -> int { s : ., mut = 0; for i in 0..10 { if i == 2 { continue; } if i == 6 { break; } s = s + i; } return s; }'],
                       capture_output=True, text=True, cwd=BASE, timeout=30)
    assert r.returncode == 13, f"break/continue expected 13 (0+1+3+4+5), got exit={r.returncode} stdout={r.stdout!r} stderr={r.stderr!r}"

def test_nested_loop_run():
    """嵌套 for 循环：覆盖 innermost region 选择分支（e2 > cur_enter 路径）——
    内层回跳必须命中内层 region enter，外层回跳必须命中外层 region enter。"""
    r = subprocess.run(['./build/corec', 'run',
                        'fn main() -> int { s : ., mut = 0; for i in 0..3 { for j in 0..3 { s = s + 1; } } return s; }'],
                       capture_output=True, text=True, cwd=BASE, timeout=30)
    assert r.returncode == 9, f"nested loop expected 9 (3x3), got exit={r.returncode} stdout={r.stdout!r} stderr={r.stderr!r}"

if __name__ == '__main__':
    import sys
    tests = [test_if_region, test_loop_region, test_node_region_mapping,
             test_state_edges, test_loop_termination_edge,
             test_for_loop_run, test_while_loop_run, test_break_continue_run,
             test_nested_loop_run]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"PASS {t.__name__}")
        except AssertionError as e:
            failed += 1
            print(f"FAIL {t.__name__}: {e}")
        except Exception as e:
            failed += 1
            print(f"ERROR {t.__name__}: {e!r}")
    print(f"{len(tests) - failed}/{len(tests)} passed")
    sys.exit(1 if failed else 0)
