# McTT 参考侧（Task 1：参考侧构建记录）

McTT（ICFP'25，Beluga-lang）——首个经 Coq 验证的 MLTT 类型检查器。本目录记录参考侧的构建与验证信息，供后续差分测试（Task 3+）harness 使用。

## 位置与版本

- 源码：`~/mctt`（**仓库外**，不提交 McTT 源码进本仓库）
- 分支：`icfp25`，头 `a3d97e9c427d311566ba25540292d55be4adfdba`（gh api 确认）
- 获取方式：curl tarball（`https://github.com/Beluga-lang/McTT/archive/refs/heads/icfp25.tar.gz`）。
  git clone 因本机到 github.com 网络不稳超时失败；tarball 亦间歇失败，重试成功。

## 构建配方（实际执行，已成功）

官方配方（README.md）为 opam 全量构建，产出提取的类型检查器：

```bash
opam update
opam switch create coq-8.20.0 4.14.2
opam pin add coq 8.20.0
opam repo add coq-released https://coq.inria.fr/opam/released
opam install -y menhir coq-equations coq-menhirlib ppx_inline_test ppx_expect
cd ~/mctt && make          # theories（Coq 证明 + extraction）→ dune build（driver）
```

**实际执行脚本：`~/mctt/build_ref.sh`**（set -e，可续跑：已建 switch/已装包一律跳过），
配套 `~/mctt/curl_gh.sh`（见「网络问题与修复」）。

### 对官方配方的必要修正

1. `opam install` 显式补装 `dune`——官方配方漏列，新建 switch 无 dune 则 `dune build` 必失败。
2. **ppx_inline_test/ppx_expect 保留不跳**——检查结论：driver/dune 的 McttLib 库有**库级**
   `(preprocess (pps ppx_expect))`，而 mctt.exe 链接 McttLib，故主构建在 dune 编译期需要
   ppx_expect 可执行文件（ppx 虽是 Test.ml inline-tests 的测试框架，但预处理指令作用于整个库）。
   结论：主构建**依赖** ppx，不能跳过；已安装成功（ppxlib.0.35.0 / ppx_inline_test.v0.16.1 /
   ppx_expect.v0.16.2）。
3. CPU 限制（仓库铁律 #6）：外层 `nice -n 19` + `OPAMJOBS=2`（opam 内 OCaml/Coq 编译）
   + `make -C theories J=2` + `dune build -j 2`。本机 4 核，全量构建约 2-3 小时。

### 网络问题与修复（github.com 主域 TLS 间歇重置）

- 现象：github.com 主域（默认 DNS 20.205.243.166）TLS 连接间歇重置（curl exit 35），
  且各 IP 不同时坏；重试 15 次仍可能全灭（曾两次卡在源码拉取、一次卡在 ppx 拉取）。
- 修复：`OPAMCURL="$HOME/mctt/curl_gh.sh"`——包装 curl 对 github.com:443 做**多 IP 轮换**
  （140.82.114.3 / 140.82.112.3 / 140.82.113.3 / 140.82.116.3 / 140.82.121.3 / 20.205.243.166），
  成功者 stdout 原样透传（opam 解析 --write-out 的 http 码）。配 `OPAMRETRIES=15` 兜底。
- codeload.github.com / raw.githubusercontent.com / release-assets.githubusercontent.com
  走正常 DNS 无问题。

## 构建状态：**COMPLETE**（2026-08-16 00:12）

- 日志：`/tmp/mctt-build.log`（尾部应见 `===== BUILD COMPLETE =====` 与
  `_build/default/driver/mctt.exe` 行）。
- switch `coq-8.20.0`（OCaml 4.14.2）：coq 8.20.0（pin）、coq-equations 1.3.1+8.20、
  coq-menhirlib 20260209、menhir 20260209、dune 3.23.1、ppx 全家已装。
- 产物：`~/mctt/_build/default/driver/mctt.exe`（6593400 字节）。

## 用法（以源码为准，已实测）

- 可执行文件：`~/mctt/_build/default/driver/mctt.exe`（**带 driver/ 段**；不是 `Main.exe`——
  driver/dune 中 executable 为 `name mctt`、模块 `Mctt.ml`，`Main.ml` 在 McttLib 库内）。
- 用法（Mctt.ml 源码确认，单参数 `<input-file>`；缺参打印 usage 并 exit 7）：

```bash
cd ~/mctt
./_build/default/driver/mctt.exe examples/simple_nat.mctt     # 直接跑，无需 switch 环境
opam exec --switch=coq-8.20.0 -- dune exec mctt -- examples/simple_nat.mctt   # 或经 dune
```

- exit 0 = 类型检查通过。注意：dune 必须在 coq-8.20.0 switch 环境跑（default switch 无 ppx_expect，
  会报 "Library ppx_expect not found"）。

## 冒烟测试结果（2026-08-16，已验证）

```text
$ ./_build/default/driver/mctt.exe examples/simple_nat.mctt
Parsed:
  4 : Nat
Elaborated:
  4 : Nat
Normalized Result:
  4 : Nat
$ echo $?    # 0
```

## extracted 模块清单（构建完成，`ls driver/extracted/*.mli` 实测 40 个）

提取代码由构建期生成（**McTT 仓库的 driver/extracted/ 本身不含任何 .ml/.mli**——icfp25 与
icfp25-artifact 标签树均已核对，只有 dune/.gitignore/.ocamlformat 三个文件）。

**McTT 核心（Task 3 harness 的差分对拍目标）：**
`Domain` `Elaborator` `Entrypoint` `Evaluation` `Interpreter` `Interpreter_complete`
`Interpreter_correct` `Main` `NbE` `Parser` `Readback` `Subtyping` `Syntax` `TypeCheck`
`Validator_complete` `Validator_safe`

**Coq 标准库提取（依赖）：**
`Alphabet` `Ascii` `Automaton` `BinInt` `BinNums` `BinPos` `Compare_dec` `Datatypes`
`FMapAVL` `FMapList` `FSetAVL` `Grammar` `Int` `List` `MSetAVL` `MSetInterface` `Nat`
`OrderedType` `Orders` `OrdersAlt` `OrdersFacts` `OrdersTac` `PeanoNat` `Specif` `String`

## 环境备注

- switch `coq-8.20.0`（OCaml 4.14.2，独立于 default switch 5.4.1）。
- 本仓库禁止 git（hook 机械拦截）；McTT 克隆/构建为第三方仓库操作，git/curl 均只作用于 ~/mctt。
