#!/usr/bin/env python3
"""铁律 #2 机械执行：Bash 命令以 git 开头 → 拒绝执行（exit 2）。"""
import json
import sys

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")
stripped = cmd.strip()

if stripped == "git" or stripped.startswith("git "):
    sys.stderr.write(
        "铁律 #2：全面使用 jj，禁止 git。\n"
        "改用 jj 命令：jj status / jj log / jj describe / jj git push / jj bookmark ...\n"
    )
    sys.exit(2)  # PreToolUse exit 2 = block the tool call
sys.exit(0)
