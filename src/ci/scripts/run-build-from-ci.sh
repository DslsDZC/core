#!/bin/bash
# Start the CI build. You shouldn't run this locally: call src/ci/run.sh instead.
# 模板来源：rust-lang/rust src/ci/scripts/run-build-from-ci.sh，按 Core 精简。

set -euo pipefail
IFS=$'\n\t'

source "$(cd "$(dirname "$0")" && pwd)/../shared.sh"

export CI="true"
export SRC=.

echo "::group::CPU and Memory information"
if [ -f /proc/cpuinfo ]; then
    grep -c processor /proc/cpuinfo | xargs echo "ncpus:"
    grep MemTotal /proc/meminfo
fi
echo "::endgroup::"

src/ci/run.sh
