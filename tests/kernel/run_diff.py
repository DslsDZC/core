import subprocess, sys, pathlib

CORE = pathlib.Path("/home/DslsDZC/core")
HARNESS = "/home/DslsDZC/mctt/_build/default/driver/harness/harness.exe"
KERNEL = str(CORE / "build/kernel")

def run(cmd, inp):
    p = subprocess.run(cmd, input=inp, capture_output=True, text=True)
    return p.stdout.splitlines()

def main():
    cases = CORE / "tests/kernel/cases"
    expd = CORE / "tests/kernel/expected"
    fails = []
    total = 0
    for name in ["exhaustive", "random", "manual"]:
        txt = (cases / f"corpus_{name}.txt").read_text()
        exp = (expd / f"corpus_{name}.expected").read_text().splitlines()
        a = run([HARNESS], txt)
        b = run([KERNEL], txt)
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
