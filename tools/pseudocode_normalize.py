#!/usr/bin/env python3
"""伪代码风格归一化：消除双重否定比较写法（语义等价的机械重写）。
- 不小于等于 → 大于        （NOT(<=) 恒等于 >）
- 不大于等于 → 小于        （NOT(>=) 恒等于 <）
- 不小于     → 大于等于    （NOT(<)  恒等于 >=）
- 不大于     → 小于等于    （NOT(>)  恒等于 <=）
用法：python3 tools/pseudocode_normalize.py [路径...]（默认 docs/pseudocode/ 下全部 .md）
要求：先替换长串再替换短串，否则会生成 "大于等于等于" 类错误。
"""
import sys
from pathlib import Path

MAP = [
    ("不小于等于", "大于"),
    ("不大于等于", "小于"),
    ("不小于", "大于等于"),
    ("不大于", "小于等于"),
]

def normalize(text: str) -> str:
    out = text
    for a, b in MAP:
        out = out.replace(a, b)
    return out

def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "docs/pseudocode"
    root = Path(arg)
    files = sorted(root.rglob("*.md")) if root.is_dir() else [root]
    changed = 0
    for f in files:
        t = f.read_text(encoding="utf-8")
        n = normalize(t)
        if n != t:
            f.write_text(n, encoding="utf-8")
            changed += 1
            print(f"normalized: {f}")
    print(f"{changed} 个文件已归一化")

if __name__ == "__main__":
    main()
