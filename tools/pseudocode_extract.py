#!/usr/bin/env python3
"""提取 Core 源码中的共享标识符，供生成伪代码术语表。用法：python3 tools/pseudocode_extract.py"""
import re, collections
from pathlib import Path

ROOTS = [Path("src/compiler"), Path("src/stdlib"),
         Path("src/runtime"), Path("src/arch/linux/ld")]
RE_FN = re.compile(r'\bfn[ \t]+([a-zA-Z_]\w*)')
RE_STRUCT = re.compile(r'\bstruct[ \t]+([A-Za-z_]\w*)')
RE_ENUM = re.compile(r'\benum[ \t]+([A-Za-z_]\w*)')
RE_GLOBAL = re.compile(r'\bg_([a-zA-Z_]\w*)')

def main():
    counts = collections.Counter()
    per_file = collections.defaultdict(list)
    for root in ROOTS:
        for f in sorted(root.glob("*.cr")):
            text = f.read_text(encoding="utf-8")
            names = set()
            for m in RE_FN.finditer(text):       names.add(("fn", m.group(1)))
            for m in RE_STRUCT.finditer(text):   names.add(("struct", m.group(1)))
            for m in RE_ENUM.finditer(text):     names.add(("enum", m.group(1)))
            for m in RE_GLOBAL.finditer(text):   names.add(("global", "g_" + m.group(1)))
            for kind, n in names:
                counts[(kind, n)] += 1
                per_file[(kind, n)].append(str(f))
    for (kind, n), c in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0][0], kv[0][1])):
        print(f"{kind}\t{n}\t{c}\t{' '.join(per_file[(kind, n)])}")

if __name__ == "__main__":
    main()
