#!/bin/bash
# Dump the environment so job logs are self-describing (mirrors the intent of
# rust-lang/rust's setup-environment.sh, minus the EXTRA_VARIABLES plumbing —
# Core jobs don't need per-job env vars yet).
set -euo pipefail
IFS=$'\n\t'

echo "::group::Environment"
echo "CI_JOB_NAME=${CI_JOB_NAME:-<unset>}"
echo "CI=${CI:-<unset>}"
echo "GITHUB_EVENT_NAME=${GITHUB_EVENT_NAME:-<unset>}"
echo "uname: $(uname -a)"
echo "python3: $(python3 --version 2>&1 || echo missing)"
echo "::endgroup::"
