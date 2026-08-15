#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""McTT→Core 内核移植 M1 差分测试语料生成器（Task 4）。

生成三个查询文件（不含期望值；期望值由 Task 7 参考 harness 生成固化）：
  tests/kernel/cases/corpus_exhaustive.txt   穷举层（size ≤ 4）
  tests/kernel/cases/corpus_random.txt       随机层（固定种子 20260815，1200 条）
  tests/kernel/cases/corpus_manual.txt       案卷（25 条经典难项）

协议（Task 3 共享格式，见 tools/mctt_ref/protocol.md）：
  check <ctx> <exp> <exp> | infer <ctx> <exp>
  convert <ctx> <exp> <exp> <exp> | subtype <ctx> <exp> <exp>
  exp ::= (typ N) | (nat) | (zero) | (succ e) | (natrec A mz ms n)
        | (pi A B) | (fn A M) | (app M N) | (var N) | (sub e s)
  sub ::= (id) | (weaken) | (compose s s) | (extend s e)
每行一条查询；corpus_exhaustive.txt 含 `#` 分层注释行（harness 与 term_io 需跳过 `#` 行）。

与 brief（.superpowers/sdd/task-4-brief.md）的差异（见 README.md）：
  1. 穷举层按 brief 的简化 natrec 方案（四子项均取 size-1 原子，最小总 size=5），
     max_size=4 下穷举层无 natrec 项；natrec 覆盖由随机层 + 案卷补齐。
  2. 案卷 6 条（第 8/9/10/16/17/21 条）brief 原文为 3 元 fn，与协议 (fn A M)
     （= McTT ti_fn: λ A M）不符，已删冗余陪域参数修正。
  3. gen_exps 返回按层分组的 dict（扁平列表语义不变，便于逐层加 `#` 注释）。
  4. 不导入 brief 中未使用的 itertools。
  5. size() 对 K_VAR（子节点为整数索引）/K_TYP（无分支）崩溃——修四类原子为
     叶节点 size=1（size 仅用于 natrec 过滤，实参恒为原子项）。
"""

import os
import random

# --- 穷举生成器（brief Step 1，原样转写） ---

K_TYP, K_NAT, K_ZERO, K_SUCC, K_NATREC, K_PI, K_FN, K_APP, K_VAR, K_SUB = range(10)
S_ID, S_WEAKEN, S_COMPOSE, S_EXTEND = range(4)


def size(t):
    """节点计数（含 sub 节点）。

    brief 原文对 K_VAR（子节点是整数索引，`1 + size(t[1])` 会崩溃）与 K_TYP
    （无分支，会 raise）未正确处理；本生成器仅在 natrec 过滤中对原子项调用，
    故四类原子一律计为叶节点 size=1（修正见 README 差异清单）。
    """
    k = t[0]
    if k in (K_TYP, K_NAT, K_ZERO, K_VAR):
        return 1
    if k in (K_SUCC, K_FN, K_APP):
        return 1 + size(t[1])
    if k in (K_PI,):
        return 1 + size(t[1]) + size(t[2])
    if k == K_NATREC:
        return 1 + size(t[1]) + size(t[2]) + size(t[3]) + size(t[4])
    if k == K_SUB:
        return 1 + size(t[1]) + ssize(t[2])
    raise ValueError(k)


def ssize(s):
    k = s[0]
    if k in (S_ID, S_WEAKEN):
        return 1
    if k == S_COMPOSE:
        return 1 + ssize(s[1]) + ssize(s[2])
    if k == S_EXTEND:
        return 1 + ssize(s[1]) + size(s[2])


def show_exp(t):
    k = t[0]
    if k == K_TYP:
        return f"(typ {t[1]})"
    if k == K_NAT:
        return "(nat)"
    if k == K_ZERO:
        return "(zero)"
    if k == K_SUCC:
        return f"(succ {show_exp(t[1])})"
    if k == K_NATREC:
        return f"(natrec {show_exp(t[1])} {show_exp(t[2])} {show_exp(t[3])} {show_exp(t[4])})"
    if k == K_PI:
        return f"(pi {show_exp(t[1])} {show_exp(t[2])})"
    if k == K_FN:
        return f"(fn {show_exp(t[1])} {show_exp(t[2])})"
    if k == K_APP:
        return f"(app {show_exp(t[1])} {show_exp(t[2])})"
    if k == K_VAR:
        return f"(var {t[1]})"
    if k == K_SUB:
        return f"(sub {show_exp(t[1])} {show_sub(t[2])})"
    raise ValueError(k)


def show_sub(s):
    k = s[0]
    if k == S_ID:
        return "(id)"
    if k == S_WEAKEN:
        return "(weaken)"
    if k == S_COMPOSE:
        return f"(compose {show_sub(s[1])} {show_sub(s[2])})"
    if k == S_EXTEND:
        return f"(extend {show_sub(s[1])} {show_exp(s[2])})"
    raise ValueError(k)


def gen_exps(max_size):
    out = {1: [(K_NAT,), (K_ZERO,), (K_VAR, 0), (K_VAR, 1), (K_TYP, 0), (K_TYP, 1)]}
    for n in range(2, max_size + 1):
        res = []
        for i in range(1, n):
            j = n - i
            for a in out.get(i, []):
                for b in out.get(j, []):
                    res += [(K_SUCC, a), (K_FN, a, b), (K_APP, a, b), (K_PI, a, b)]
        # 注：natrec 组合保持简单——只枚举 a,b,c,d 均为 size-1 项的组合（最小总 size=5，
        # 故 max_size=4 时本行不命中；natrec 覆盖由随机层 + 案卷补齐，见 README）
        res += [(K_NATREC, a, b, c, d)
                for a in out.get(1, []) for b in out.get(1, [])
                for c in out.get(1, []) for d in out.get(1, [])
                if n == 1 + size(a) + size(b) + size(c) + size(d)]
        res += [(K_SUB, a, (S_ID,)) for a in out.get(n - 1, [])]
        seen = set()
        out[n] = []
        for x in res:                       # 按 show_exp 文本去重
            s = show_exp(x)
            if s not in seen:
                seen.add(s)
                out[n].append(x)
    # brief 原文返回扁平列表；此处返回按层 dict（main 里展平，语义不变）
    return out


# --- 随机生成器（brief Step 3，原样转写） ---

def rand_exp(rng, depth, max_var):
    k = rng.randrange(10)
    if k in (K_NAT, K_ZERO):
        return (k,)
    if k == K_VAR:
        return (K_VAR, rng.randrange(max_var))
    if k in (K_SUCC, K_FN, K_APP, K_PI) and depth > 0:
        a = rand_exp(rng, depth - 1, max_var)
        b = rand_exp(rng, depth - 1, max_var)
        return (k, a) if k == K_SUCC else (k, a, b)
    if k == K_NATREC and depth > 1:
        return (K_NATREC, rand_exp(rng, depth - 2, max_var),
                rand_exp(rng, depth - 2, max_var),
                rand_exp(rng, depth - 2, max_var),
                rand_exp(rng, depth - 2, max_var))
    if k == K_SUB and depth > 0:
        return (K_SUB, rand_exp(rng, depth - 1, max_var),
                rng.choice([(S_ID,), (S_WEAKEN,)]))
    return (K_NAT,)


# --- 发射配置 ---

MAX_SIZE = 4             # 穷举层规模（brief：size ≤ 4）
RANDOM_SEED = 20260815   # 固定种子（brief Step 3）
RANDOM_COUNT = 1200      # 随机层条数
CONVERT_CAP = 50         # convert 仅对穷举前 50 项
CTX_POOL = ["(ctx)", "(ctx (nat))", "(ctx (typ 0))", "(ctx (nat) (nat))"]


def is_type_shaped(t):
    """类型形态：首构造子为 pi/typ/nat"""
    return t[0] in (K_PI, K_TYP, K_NAT)


def emit_exhaustive(path, out):
    """穷举层发射（brief Step 2）。

    对每项 t 发射 infer/check×2；前 CONVERT_CAP 项加 convert；类型形态项加 subtype×2；
    再以 (ctx (nat)) 与 (ctx (typ 0)) 上下文重复 infer/check。`#` 行注释标明来源层。
    """
    total = sum(len(out[n]) for n in range(1, MAX_SIZE + 1))
    with open(path, "w") as f:
        f.write("# corpus_exhaustive.txt — 穷举层（size <= %d，共 %d 项）\n" % (MAX_SIZE, total))
        f.write("# 协议：Task 3 共享格式；每行一条查询；# 开头的行是注释，harness 与 term_io 需跳过\n")
        f.write("# 生成：python3 tests/kernel/gen_corpus.py（种子 %d）\n" % RANDOM_SEED)
        idx = 0
        for n in range(1, MAX_SIZE + 1):
            bucket = out.get(n, [])
            f.write("# 穷举层 size=%d（%d 项），上下文 (ctx)\n" % (n, len(bucket)))
            for t in bucket:
                s = show_exp(t)
                f.write("infer (ctx) %s\n" % s)
                f.write("check (ctx) %s (nat)\n" % s)
                f.write("check (ctx) %s (typ 0)\n" % s)
                if idx < CONVERT_CAP:
                    f.write("convert (ctx) %s (nat) (typ 0)\n" % s)
                if is_type_shaped(t):
                    f.write("subtype (ctx) %s (nat)\n" % s)
                    f.write("subtype (ctx) (nat) %s\n" % s)
                idx += 1
        for ctx in ("(ctx (nat))", "(ctx (typ 0))"):
            f.write("# 上下文 %s：重复 infer/check（全部 %d 项）\n" % (ctx, total))
            for n in range(1, MAX_SIZE + 1):
                for t in out.get(n, []):
                    s = show_exp(t)
                    f.write("infer %s %s\n" % (ctx, s))
                    f.write("check %s %s (nat)\n" % (ctx, s))
                    f.write("check %s %s (typ 0)\n" % (ctx, s))


def rand_term(rng):
    """随机项：深度 1-3，变量上限 2-3"""
    depth = rng.randrange(1, 4)
    max_var = rng.choice([2, 3])
    return rand_exp(rng, depth, max_var)


def rand_type_target(rng):
    """check/convert 的目标类型：60% 类型形态，40% 随机项"""
    r = rng.randrange(5)
    if r == 0:
        return (K_NAT,)
    if r == 1:
        return (K_TYP, 0)
    if r == 2:
        return (K_TYP, 1)
    return rand_exp(rng, 2, 2)


def rand_typeish(rng):
    """subtype 两侧：40% 类型形态（nat/typ/pi），否则随机项"""
    if rng.random() < 0.4:
        return rng.choice([(K_NAT,), (K_TYP, 0), (K_TYP, 1),
                           (K_PI, rand_exp(rng, 2, 2), rand_exp(rng, 2, 2))])
    return rand_term(rng)


def emit_random(path, rng, count=RANDOM_COUNT):
    """随机层发射（brief Step 3）：infer 为主 + check/convert/subtype 混合。

    上下文随机选自 (ctx)、(ctx (nat))、(ctx (typ 0))、(ctx (nat) (nat))。
    查询类别权重：infer 50% / check 20% / convert 15% / subtype 15%。
    """
    kinds = ["infer"] * 10 + ["check"] * 4 + ["convert"] * 3 + ["subtype"] * 3
    with open(path, "w") as f:
        for _ in range(count):
            ctx = rng.choice(CTX_POOL)
            kind = rng.choice(kinds)
            if kind == "infer":
                line = "infer %s %s" % (ctx, show_exp(rand_term(rng)))
            elif kind == "check":
                line = "check %s %s %s" % (ctx, show_exp(rand_term(rng)),
                                           show_exp(rand_type_target(rng)))
            elif kind == "convert":
                line = "convert %s %s %s %s" % (ctx, show_exp(rand_term(rng)),
                                                show_exp(rand_term(rng)),
                                                show_exp(rand_type_target(rng)))
            else:  # subtype
                line = "subtype %s %s %s" % (ctx, show_exp(rand_typeish(rng)),
                                             show_exp(rand_typeish(rng)))
            f.write(line + "\n")


# --- 案卷（brief Step 4，25 条 exact content） ---
# 与 brief 原文的差异：第 8/9/10/21 条 `fn (nat) (nat|typ0|typ1) (var 0)`、
# 第 16/17 条 natrec 步进 `fn (nat) (nat) (succ (var 0))` 均为 3 元 fn，
# 与协议 (fn A M)（= McTT ti_fn `λ A M`）不符，已删冗余陪域参数修正。

MANUAL_QUERIES = [
    "check (ctx) (zero) (nat)",                                              # 基例检查
    "check (ctx) (zero) (typ 0)",                                            # 类型错误
    "infer (ctx) (succ (succ (zero)))",                                      # 嵌套 succ
    "check (ctx) (app (fn (nat) (var 0)) (zero)) (nat)",                     # β 归约后正确
    "check (ctx) (app (fn (nat) (var 0)) (zero)) (typ 0)",                   # 类型不匹配
    "check (ctx) (app (var 0) (zero)) (nat)",                                # 变量类型未知（ctx 空）
    "check (ctx (nat)) (app (var 0) (zero)) (nat)",                          # 上下文中变量可用
    "infer (ctx) (fn (nat) (var 0))",                                        # λ 推断
    "check (ctx) (fn (nat) (var 0)) (pi (nat) (nat))",                       # Π 检查
    "check (ctx) (fn (nat) (var 0)) (pi (nat) (typ 0))",                     # 陪域宇宙
    "subtype (ctx) (typ 0) (typ 1)",                                         # 累积
    "subtype (ctx) (typ 1) (typ 0)",                                         # 反向拒绝
    "subtype (ctx) (nat) (nat)",                                             # 自反
    "convert (ctx) (app (fn (nat) (var 0)) (zero)) (zero) (nat)",            # β 转换
    "convert (ctx) (pi (nat) (nat)) (pi (nat) (nat)) (typ 1)",               # Π 自反
    "infer (ctx) (natrec (nat) (zero) (fn (nat) (succ (var 0))) (succ (zero)))",   # natrec 全展开
    "check (ctx) (natrec (nat) (zero) (fn (nat) (succ (var 0))) (zero)) (nat)",    # natrec zero 分支
    "check (ctx) (sub (var 0) (weaken)) (nat)",                              # 显式替换：weaken
    "check (ctx (nat) (nat)) (sub (var 0) (compose (weaken) (id))) (nat)",   # 替换组合
    "infer (ctx) (sub (succ (var 0)) (extend (id) (zero)))",                 # extend 替换
    "check (ctx) (fn (nat) (var 0)) (pi (nat) (typ 1))",                     # 高宇宙
    "infer (ctx) (app (fn (typ 0) (var 0)) (nat))",                          # 宇宙作为类型（多层）
    "check (ctx (typ 0)) (var 0) (typ 1)",                                   # 上下文类型变量
    "convert (ctx) (sub (var 0) (extend (id) (zero))) (zero) (nat)",         # q 替换展开
    "check (ctx) (nat) (typ 0)",                                             # 类型 Type
]


def line_count(path):
    with open(path) as f:
        return sum(1 for _ in f)


def main():
    cases = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cases")
    os.makedirs(cases, exist_ok=True)

    out = gen_exps(MAX_SIZE)
    n_terms = sum(len(out[n]) for n in range(1, MAX_SIZE + 1))
    print("穷举层：size<=%d 共 %d 项" % (MAX_SIZE, n_terms))
    for n in range(1, MAX_SIZE + 1):
        print("  size=%d：%d 项" % (n, len(out[n])))

    p1 = os.path.join(cases, "corpus_exhaustive.txt")
    emit_exhaustive(p1, out)

    rng = random.Random(RANDOM_SEED)
    p2 = os.path.join(cases, "corpus_random.txt")
    emit_random(p2, rng)

    p3 = os.path.join(cases, "corpus_manual.txt")
    with open(p3, "w") as f:
        for q in MANUAL_QUERIES:
            f.write(q + "\n")

    # 自检（brief Step 5 验收线）
    l1, l2, l3 = line_count(p1), line_count(p2), line_count(p3)
    assert l1 >= 300, "corpus_exhaustive.txt 行数 %d < 300" % l1
    assert l2 == RANDOM_COUNT, "corpus_random.txt 行数 %d != %d" % (l2, RANDOM_COUNT)
    assert l3 == len(MANUAL_QUERIES), "corpus_manual.txt 行数 %d != %d" % (l3, len(MANUAL_QUERIES))
    print("生成完成（自检通过）：")
    print("  %s  %d 行" % (p1, l1))
    print("  %s  %d 行" % (p2, l2))
    print("  %s  %d 行" % (p3, l3))


if __name__ == "__main__":
    main()
