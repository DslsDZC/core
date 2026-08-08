#!/usr/bin/env python3
"""Region-based control flow tests — dump .cir text and assert region structure."""
import os, subprocess, tempfile

BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COREC = os.path.join(BASE, 'build/corec')

def cir_dump(src: str) -> str:
    with tempfile.NamedTemporaryFile('w', suffix='.cr', delete=False) as f:
        f.write(src)
        path = f.name
    r = subprocess.run(['./build/corec', 'cir', path], capture_output=True, text=True,
                       cwd=BASE, timeout=30)
    os.unlink(path)
    return r.stdout

def test_if_region():
    out = cir_dump("fn f(x: int) -> int {\n    if x > 0 { return 1; }\n    return 0;\n}\nfn main() -> int { return f(1); }\n")
    assert 'Region: if' in out, f"SG_IF region missing in cir dump:\n{out}"

def test_loop_region():
    out = cir_dump("fn main() -> int {\n    s : ., mut = 0;\n    for i in 0..3 { s = s + i; }\n    return s;\n}\n")
    assert 'Region: for' in out, f"SG_FOR region missing in cir dump:\n{out}"
