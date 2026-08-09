#!/usr/bin/env bash

# Core CI job 分发器——按 $CI_JOB_NAME 执行对应 job 的命令集。
# 本地复现：CI_JOB_NAME=check src/ci/run.sh
# 注意：本地长时间编译请遵守 CLAUDE.md 铁律 6（cpulimit/nice 限速）。
#
# 模板来源：rust-lang/rust src/ci/run.sh（configure/make 部分替换为 Core 构建命令）。

CI_JOB_NAME="${CI_JOB_NAME:-}"
set -euo pipefail
IFS=$'\n\t'

if [ -n "$CI_JOB_NAME" ]; then
  echo "[CI_JOB_NAME=$CI_JOB_NAME]"
fi

ci_dir="$(cd "$(dirname "$0")" && pwd)"
source "$ci_dir/shared.sh"

# 自举构建：Python bootstrap → 原生 corec/corearch
build_selfhost() {
  python3 build_selfhost_native.py
}

# src/compiler 全量语法检查（check 不触发 ELF 后端）
check_compiler_sources() {
  for f in src/compiler/*.cr; do
    echo "check $f"
    ./build/corec check "$f"
  done
}

# 集成套件：每个 .cr 编译成 ELF 并运行，main 返回 0 为通过
run_suite() {
  for f in tests/suite/*.cr; do
    echo "suite: $f"
    ./build/corec build "$f" -o /tmp/core_suite_bin --static
    /tmp/core_suite_bin
  done
}

case "$CI_JOB_NAME" in
  check)
    build_selfhost
    check_compiler_sources
    ;;

  bootstrap-tests)
    python3 tests/bootstrap/test_pipeline.py
    python3 tests/bootstrap/test_borrow.py
    python3 tests/bootstrap/test_generics.py
    ;;

  selfhost-tests)
    python3 tests/selfhost/test_compile.py
    python3 tests/selfhost/test_impl.py
    python3 tests/selfhost/test_borrow.py
    ;;

  suite)
    build_selfhost
    run_suite
    ;;

  full-bootstrap)
    # 三阶段自举验证（corec → corec2 → corec3）按 TODO 逐步点亮。
    # stage-2：用自举产物编译编译器自身（main.cr 经 imports 拉全编译器）。
    # 已知风险：corec2 tokenizer 死循环（TODO 自举阻塞项）+ 预存 bug 1
    # （1GiB bump heap 峰值）——CI 上可能失败/超时/OOM，点亮前如实标记。
    build_selfhost
    ./build/corec build src/compiler/main.cr -o /tmp/corec2 --static
    /tmp/corec2 --help
    ;;

  *)
    echo "error: unknown CI_JOB_NAME: $CI_JOB_NAME" >&2
    exit 1
    ;;
esac
