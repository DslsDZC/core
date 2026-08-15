# McTT 参考侧（Task 1：参考侧构建记录）

McTT（ICFP'25，Beluga-lang）——首个经 Coq 验证的 MLTT 类型检查器。本目录记录参考侧的构建与验证信息，供后续差分测试（Task 3+）harness 使用。

## 位置与版本

- 源码：`~/mctt`（**仓库外**，不提交 McTT 源码进本仓库）
- 分支：`icfp25`，头 `a3d97e9c427d311566ba25540292d55be4adfdba`（gh api 确认）
- 获取方式：curl tarball（`https://github.com/Beluga-lang/McTT/archive/refs/heads/icfp25.tar.gz`）。
  git clone 因本机到 github.com 网络不稳超时失败；tarball 亦间歇失败，重试成功。

## 构建配方

官方配方（README.md）为 opam 全量构建，产出提取的类型检查器：

```bash
opam update
opam switch create coq-8.20.0 4.14.2
opam pin add coq 8.20.0
opam repo add coq-released https://coq.inria.fr/opam/released
opam install -y menhir coq-equations coq-menhirlib ppx_inline_test ppx_expect
cd ~/mctt && make          # theories（Coq 证明 + extraction）→ dune build（driver）
```

**实际执行脚本：`~/mctt/build_ref.sh`**（set -e，含下述两处修正 + CPU 限制）：

1. `opam install` 显式补装 `dune`——官方配方漏列，新 switch 无 dune 则 `dune build` 必失败。
2. `OPAMCURL="$HOME/mctt/curl_gh.sh"`——本机到 github.com 主域 TLS 间歇重置（默认 DNS
   20.205.243.166 不稳，15 次重试仍失败）；包装 curl 固定 `--resolve github.com:443:140.82.114.3`
   （实测 4/4 成功）。codeload / raw.githubusercontent.com 走正常 DNS 无问题。

CPU 限制（仓库铁律 #6）：外层 `nice -n 19` + `OPAMJOBS=2`（opam 内 OCaml/Coq 编译）
+ `make -C theories J=2` + `dune build -j 2`。

## 当前构建状态

- 日志：`/tmp/mctt-build.log`（`setsid nohup nice -n 19 bash ~/mctt/build_ref.sh > /tmp/mctt-build.log 2>&1 &`）
- 启动时间：2026-08-15 22:4x；预期 2-4 小时。
- 已确认推进：`opam switch create coq-8.20.0 4.14.2` 源码拉取成功 → OCaml 4.14.2 编译中
  （`make opt.opt` / `make -C runtime allopt`，-j2 / nice 16）。

## Main.exe 用法（实际以源码为准）

- 可执行文件：`~/mctt/_build/default/mctt.exe`（**不是 `Main.exe`** —— `driver/dune` 中
  executable 为 `name mctt`、模块 `Mctt.ml`；`Main.ml` 在 McttLib 库内，被 Mctt.ml 调 `McttLib.Main.main_of_filename`）。
- 用法（Mctt.ml 源码确认，单参数）：

```bash
cd ~/mctt
dune exec mctt -- examples/simple_nat.mctt     # 或 ./_build/default/mctt.exe examples/simple_nat.mctt
```

- exit 0 = 类型检查通过；参数个数不对打印 usage 并 exit 7。

## 构建完成后的验证命令（Task 3 前必须绿）

```bash
cd ~/mctt && dune exec mctt -- examples/simple_nat.mctt   # 冒烟：接受 simple_nat
ls ~/mctt/driver/extracted/*.mli                          # 模块清单，粘入下方
tail -5 /tmp/mctt-build.log                               # 应有 "===== BUILD COMPLETE ====="
```

## extracted 模块清单（待构建完成后填写）

预期来源（构建期生成，仓库不含任何 .ml/.mli——icfp25 与 icfp25-artifact 标签树均已核对）：
- menhir 生成：`Parser.ml/.mli`、`Entrypoint.ml/.mli`（theories/Frontend 的 .vy → Coq → 提取）
- Coq 提取（theories/Extraction/）：TypeCheck、NbE、Evaluation、Readback、Subtyping、PseudoMonadic

```text
（构建完成后 `ls driver/extracted/*.mli` 的输出粘这里）
```

## 环境备注

- switch `coq-8.20.0`（OCaml 4.14.2，独立于 default switch 5.4.1）；Coq 8.20.0、coq-equations 1.3.1+8.20、
  coq-menhirlib、menhir 均按官方版本。
- 本仓库禁止 git（hook 机械拦截）；McTT 克隆为第三方仓库操作，git/curl 均只作用于 ~/mctt。
