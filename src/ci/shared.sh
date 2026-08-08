#!/bin/false
# shellcheck shell=bash

# This file is intended to be sourced with `. shared.sh` or
# `source shared.sh`, hence the invalid shebang and not being
# marked as an executable file in git.
#
# 模板来源：rust-lang/rust src/ci/shared.sh，按 Core 精简。

function retry {
  echo "Attempting with retry:" "$@"
  local n=1
  local max=5
  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        sleep $n  # don't retry immediately
        ((n++))
        echo "Command failed. Attempt $n/$max:"
      else
        echo "The command has failed after $n attempts."
        return 1
      fi
    }
  done
}

function isCI {
    [[ "${CI-false}" = "true" ]] || isGitHubActions
}

function isGitHubActions {
    [[ "${GITHUB_ACTIONS-false}" = "true" ]]
}
