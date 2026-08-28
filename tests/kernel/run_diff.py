import subprocess, sys, pathlib

CORE = pathlib.Path("/home/DslsDZC/core")
HARNESS = "/home/DslsDZC/mctt/_build/default/driver/harness/harness.exe"
KERNEL = str(CORE / "build/kernel")

def run(cmd, path):
    # 两侧均为文件参数模式（protocol.md §7：QUERY_FILE...；Core 无 stdin API）
    p = subprocess.run([*cmd, path], capture_output=True, text=True)
    return p.stdout.splitlines(), p.returncode

def main():
    cases = CORE / "tests/kernel/cases"
    expd = CORE / "tests/kernel/expected"
    fails = []
    total = 0
    for name in ["exhaustive", "random", "manual"]:
        path = str(cases / f"corpus_{name}.txt")
        exp = (expd / f"corpus_{name}.expected").read_text().splitlines()
        a, ra = run([HARNESS], path)
        b, rb = run([KERNEL], path)
        if ra != 0:
            fails.append((name, "harness-exit", ra, "", ""))
        if rb != 0:
            fails.append((name, "kernel-exit", rb, "", ""))
        assert len(a) == len(exp) == len(b), (name, len(a), len(exp), len(b))
        for i, (x, y, e) in enumerate(zip(a, b, exp)):
            total += 1
            if x != e or y != e:
                fails.append((name, i, x, y, e))
    print(f"total={total} ok={total-len(fails)} fail={len(fails)}")
    for f in fails[:20]:
        print(f)
    sys.exit(1 if fails else 0)

main()
