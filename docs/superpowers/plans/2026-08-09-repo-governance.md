# 仓库治理落地 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将已批准的仓库治理设计（spec `docs/superpowers/specs/2026-08-09-repo-governance-design.md`）落地：本地 jj 保护/签名/hook、develop 集成分支、GitHub 双 ruleset、签名密钥注册、端到端验证。

**Architecture:** GitFlow（feature → develop → main，main 仅维护者合入）。GitHub 侧用 ruleset（main/develop 两个）+ merge queue；本地侧用 jj 配置（bookmark protect、SSH 签名）+ Claude Code PreToolUse hook（铁律 #2 机械执行）。CI 已实现（上阶段完成），本计划将其 job 名接入 ruleset 状态检查。

**Tech Stack:** jj 0.44（colocated）、Claude Code hooks、gh CLI / GitHub Rulesets REST API、GitHub Web UI、GitFlow 分支模型。

## Global Constraints

- **版本控制：全面 jj，禁止 git**（CLAUDE.md 铁律 #2；Task 3 落地 hook 后机械拦截。本计划内所有"提交"步骤一律 `jj describe`/`jj git push`，写 `git` 命令即违规）
- **编译限速**（铁律 #6）：本计划无长时间编译任务；若验证步骤意外触发构建，加 `cpulimit -l 10` 或 `nice -n 19`
- **ruleset 目标（spec §3.1 M1-M7 / §3.2 D1-D11）**：main 仅维护者可更新（update 规则 + bypass_actors 不含 Admin）、禁强推、禁删、PR 门槛（≥1 审批 + 对话解决 + stale 作废）、签名提交、无管理员绕过、protected tags `release/*`；develop：PR 唯一通道、审批限维护者、merge queue（SQUASH）、CI 状态检查（CI / check、CI / bootstrap-tests、CI / selfhost-tests）、squash only + 自动删分支、核心路径保护（src/compiler/**、src/arch/**）
- **过渡**：两个 ruleset 先 `enforcement: evaluate`，验证无干扰后转 `active`
- **签名**：`signing.backend=ssh`、`signing.key=~/.ssh/id_ed25519.pub`、`signing.sign-all=true`；GitHub 侧公钥须注册为 **Signing key**（Task 8）
- **PR 一律 base=develop**（CONTRIBUTING 已写入）；develop→main 合入仅 DslsDZC
- **已知风险（不阻塞本计划）**：CI full-bootstrap job 撞 corec2 自举阻塞项（TODO），点亮属后续项

---

### Task 1: jj bookmark protect（本地防手滑）

**Files:** 无（jj repo 配置）

**Interfaces:**
- Produces: `bookmarks.main.protect = true`（repo 级配置）——Task 9 验证依赖

- [ ] **Step 1: 设置保护**

```bash
jj config set --repo bookmarks.main.protect true
```

- [ ] **Step 2: 验证配置生效**

```bash
jj config get bookmarks.main.protect
```
Expected: `true`

- [ ] **Step 3: 验证行为（rebase 不能挪动 main）**

```bash
# main 已被保护：对 main 做 rewrite 操作会被拒绝
jj rebase -r 'main' -A main 2>&1 || echo "REJECTED as expected"
```
Expected: 命令报错（protected bookmark 不能隐式移动）或 `REJECTED as expected`。若意外成功则回退（`jj undo`）并检查 `bookmarks.main.protect` 值。

- [ ] **Step 4: 提交（jj）**

```bash
jj describe -m "chore(governance): jj main bookmark 保护"
```

### Task 2: jj SSH 提交签名

**Files:** 无（jj user 配置）

**Interfaces:**
- Produces: `signing.backend=ssh`、`signing.key=~/.ssh/id_ed25519.pub`、`signing.sign-all=true`——Task 3 的提交即首个签名提交（在 Task 3 Step 4 验证签名）

- [ ] **Step 1: 配置签名**

```bash
jj config set --user signing.backend ssh
jj config set --user signing.key /home/DslsDZC/.ssh/id_ed25519.pub
jj config set --user signing.sign-all true
```

- [ ] **Step 2: 验证配置**

```bash
jj config get signing.backend   # Expected: ssh
jj config get signing.key       # Expected: /home/DslsDZC/.ssh/id_ed25519.pub
jj config get signing.sign-all  # Expected: true
```

- [ ] **Step 3: 确认公钥存在**

```bash
ls -la /home/DslsDZC/.ssh/id_ed25519.pub   # Expected: 文件存在
```

- [ ] **Step 4: 提交（jj）**

```bash
jj describe -m "chore(governance): jj SSH 提交签名（sign-all）"
```

### Task 3: git 硬拦截 hook（铁律 #2 机械执行）

**Files:**
- Create: `.claude/hooks/block-git.py`
- Create: `.claude/settings.json`

**Interfaces:**
- Produces: `.claude/settings.json` 的 PreToolUse hook——Task 4 依赖（settings.local.json 清理后权限模型一致）；Task 9 验证

- [ ] **Step 1: 写 hook 脚本**

Create `.claude/hooks/block-git.py`:

```python
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
```

- [ ] **Step 2: 写 settings.json（提交入库）**

Create `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 .claude/hooks/block-git.py"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 3: 验证 hook 脚本逻辑（直接喂 JSON）**

```bash
# git 命令 → 应被拒绝（exit 2）
echo '{"tool_input": {"command": "git status"}}' | python3 .claude/hooks/block-git.py; echo "exit=$?"
# jj 命令 → 应放行（exit 0）
echo '{"tool_input": {"command": "jj status"}}' | python3 .claude/hooks/block-git.py; echo "exit=$?"
```
Expected: 第一次 `exit=2` 且 stderr 有铁律提示；第二次 `exit=0`。

- [ ] **Step 4: 验证签名生效（本提交是 sign-all 后的首个提交）**

```bash
jj describe -m "feat(governance): 铁律 #2 git 拦截 hook（.claude/settings.json）"
jj log -r @ --no-graph -T 'signature.format()'
```
Expected: describe 成功后，签名模板输出非空（SSH 签名信息）。若为空，检查 Task 2 配置与 `jj sign --help`。

- [ ] **Step 5: 验证 hook 在会话内拦截**

在 Claude Code 会话中执行 `git status`（作为测试）：
Expected: 工具调用被 PreToolUse hook 阻断，反馈显示"铁律 #2：全面使用 jj，禁止 git"。

### Task 4: settings.local.json 清理（移除 git 允许项）

**Files:**
- Modify: `.claude/settings.local.json`（移除 `"Bash(git *)",` 一行）

**Interfaces:**
- Consumes: Task 3 的 hook（拦截已生效）
- Produces: 权限模型与 hook 一致——Task 9 验证

- [ ] **Step 1: 移除允许项**

编辑 `.claude/settings.local.json`，删除 permissions.allow 数组中的这一行：

```json
      "Bash(git *)",
```

- [ ] **Step 2: 验证无残留**

```bash
grep -n 'Bash(git' .claude/settings.local.json; echo "exit=$?"
```
Expected: 无输出（grep 找不到），exit=1。

- [ ] **Step 3: 验证 JSON 仍合法**

```bash
python3 -c "import json; json.load(open('.claude/settings.local.json')); print('JSON OK')"
```
Expected: `JSON OK`

- [ ] **Step 4: 提交（jj）**

```bash
jj describe -m "chore(governance): settings.local.json 移除 Bash(git *) 允许项"
```

### Task 5: CLAUDE.md 版本控制流程段

**Files:**
- Modify: `CLAUDE.md`（在"Build & Test Commands"之前插入新段）

**Interfaces:**
- Produces: CLAUDE.md 的"版本控制流程"段——Task 9 核对文档与机制一致

- [ ] **Step 1: 插入流程段**

在 `CLAUDE.md` 的 `## Build & Test Commands` 之前插入：

```markdown
## 版本控制流程（GitFlow）

- 全面使用 `jj`（铁律 #2，hook 机械拦截 git）。分支模型：feature → develop → main
- **main = 正式版线**：仅维护者 DslsDZC 可合入（ruleset：update 规则 + 无管理员绕过）
- **develop = 集成分支**：日常 PR 目标（ruleset：PR 通道 + 审批 + merge queue + CI 门槛）
- 日常开发（feature → develop）：

```bash
jj bookmark create feature/xxx        # 每个改动独立分支（base = develop）
# ...开发提交（SSH 自动签名）...
jj git push -b feature/xxx
gh pr create --base develop --fill    # PR 指向 develop（"不能指向 main"）
# → 审查 → merge queue → squash 合入 develop → 自动删源分支
jj git fetch && jj bookmark move develop -r develop@origin
```

- 发布（develop → main，仅维护者）：

```bash
jj git push -b develop
gh pr create --base main --fill       # required reviewers = 你 → 你批准 → queue 合入
```

- 合入 main 后（发布线）：

```bash
jj git fetch && jj bookmark move main -r main@origin
```
```

- [ ] **Step 2: 验证插入**

```bash
grep -n "版本控制流程\|develop = 集成分支" CLAUDE.md
```
Expected: 两行都在，位置在 Build & Test Commands 之前。

- [ ] **Step 3: 提交（jj）**

```bash
jj describe -m "docs: CLAUDE.md 版本控制流程段（GitFlow 工作流命令）"
```

### Task 6: 创建并推送 develop 集成分支

**Files:** 无（分支操作）

**Interfaces:**
- Produces: `develop` bookmark（本地 + origin@）——Task 7 的 develop ruleset 目标、Task 9 验证

- [ ] **Step 1: 本地创建 develop（从远端 main 派生）**

```bash
jj bookmark create develop -r 'main@origin'
```

- [ ] **Step 2: 推送 develop 到 origin**

```bash
jj git push -b develop
```
Expected: `bookmark: develop [add to <sha>]`

- [ ] **Step 3: 验证**

```bash
jj bookmark list develop
jj log -r develop@origin --no-graph -T 'commit_id.short()'
```
Expected: develop@origin 存在，指向与 main 相同的提交。

- [ ] **Step 4: 提交说明（jj）**

```bash
jj describe -m "chore(governance): 创建 develop 集成分支（GitFlow）"
```

### Task 7: GitHub ruleset 配置（main + develop）

**Files:**
- Create: `tools/gh_setup_ruleset.sh`（内含两个 ruleset 的 JSON 载荷）

**Interfaces:**
- Consumes: Task 6 的 develop 分支（ruleset 目标存在）；CI job 名（.github/workflows/ci.yml：`CI / check`、`CI / bootstrap-tests`、`CI / selfhost-tests`）
- Produces: 两个 ruleset（evaluate 模式）——Task 9 验证

- [ ] **Step 1: 写配置脚本**

Create `tools/gh_setup_ruleset.sh`:

```bash
#!/bin/bash
# 仓库治理 ruleset 配置脚本（spec §3 清单落地，路径 A）
# 用法：gh auth refresh 后运行本脚本；或按脚本内 JSON 在网页版手动配置（路径 B）
# API 事实：restrict-pushes = update 规则 + bypass_actors（不含 Admin 角色=关闭管理员绕过）；
#           required_reviewers 为 pull_request 规则的 beta 参数（Team 型）——个人用户用
#           bypass_actors 空集 + 权限模型（仅 DslsDZC 有写权限）实现。
set -euo pipefail
REPO="dslsdzc/core"

main_ruleset() {
cat <<'JSON'
{
  "name": "main-only-maintainer",
  "target": "branch",
  "enforcement": "evaluate",
  "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
  "bypass_actors": [],
  "rules": [
    {"type": "update", "parameters": {"update_allows_fetch_and_merge": false}},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 1,
      "dismiss_stale_reviews_on_push": true,
      "require_last_push_approval": false,
      "required_review_thread_resolution": true
    }},
    {"type": "required_signatures"},
    {"type": "non_fast_forward"},
    {"type": "deletion"}
  ]
}
JSON
}

develop_ruleset() {
cat <<'JSON'
{
  "name": "develop-integration",
  "target": "branch",
  "enforcement": "evaluate",
  "conditions": {"ref_name": {"include": ["refs/heads/develop"], "exclude": []}},
  "bypass_actors": [],
  "rules": [
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 1,
      "dismiss_stale_reviews_on_push": true,
      "require_last_push_approval": false,
      "required_review_thread_resolution": true
    }},
    {"type": "required_status_checks", "parameters": {
      "checks": [
        {"context": "CI / check"},
        {"context": "CI / bootstrap-tests"},
        {"context": "CI / selfhost-tests"}
      ],
      "strict_required_status_checks_policy": true
    }},
    {"type": "merge_queue", "parameters": {
      "check_response_timeout_minutes": 60,
      "grouping_strategy": "ALLGREEN",
      "max_entries_to_build": 5,
      "max_entries_to_merge": 2,
      "merge_method": "SQUASH",
      "min_entries_to_merge": 1,
      "min_entries_to_merge_wait_minutes": 1
    }},
    {"type": "non_fast_forward"},
    {"type": "deletion"}
  ]
}
JSON
}

main_ruleset  > /tmp/main_ruleset.json
develop_ruleset > /tmp/develop_ruleset.json
echo "== main ruleset payload =="
cat /tmp/main_ruleset.json
echo "== develop ruleset payload =="
cat /tmp/develop_ruleset.json

if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  gh api -X POST "repos/${REPO}/rulesets" --input /tmp/main_ruleset.json
  gh api -X POST "repos/${REPO}/rulesets" --input /tmp/develop_ruleset.json
  echo "== 已创建 rulesets =="
  gh api "repos/${REPO}/rulesets" --jq '.[] | {name, enforcement}'
else
  echo "gh 不可用：请按上方 JSON 在网页版 Settings → Rules → Rulesets 手动创建（路径 B）"
fi
```

- [ ] **Step 2: 验证脚本语法**

```bash
bash -n tools/gh_setup_ruleset.sh && echo "syntax OK"
```
Expected: `syntax OK`

- [ ] **Step 3: 验证 JSON 载荷合法**

```bash
bash tools/gh_setup_ruleset.sh 2>&1 | grep -A5 "payload" ; python3 -c "import json; [json.load(open(p)) for p in ['/tmp/main_ruleset.json','/tmp/develop_ruleset.json']]; print('JSON OK')"
```
Expected: `JSON OK`（gh 不可用时会打印路径 B 提示——正常，此环境 gh 故障）

- [ ] **Step 4: 提交（jj）**

```bash
jj describe -m "feat(governance): ruleset 配置脚本（main/develop，evaluate 模式，双路径）"
```

- [ ] **Step 5: 落地（二选一，gh 恢复后走 A，否则走 B）**

路径 A（gh 恢复后）：
```bash
gh auth refresh -h github.com
bash tools/gh_setup_ruleset.sh
```
Expected: 创建成功，`gh api repos/dslsdzc/core/rulesets --jq '.[] | {name, enforcement}'` 显示两个 ruleset（evaluate）。

路径 B（gh 故障期，网页版）——按 spec §3.1/§3.2 清单 + 本脚本 JSON 在 Settings → Rules → Rulesets 创建：
1. New ruleset → 名称 `main-only-maintainer` → Target: `main`（默认分支）
2. Enforcement: **Evaluate**（先试运行）
3. Rules: Block force pushes / Restrict deletions / Require a pull request before merging（1 approval、Dismiss stale approvals、Require conversation resolution）
4. Require signed commits；Rules 列表确认 **Restrict pushes** 生效且 **Repository admin 不在 bypass 列表**（"Enforce for admins"）
5. 保存；重复创建 `develop-integration`（Target: develop）：
   - Require a pull request before merging（1 approval、stale 作废、对话解决）
   - Require status checks：勾选 CI / check、CI / bootstrap-tests、CI / selfhost-tests（若 PR CI 尚未跑过则稍后回填）
   - Require merge queue（squash merge、60min 超时）
   - Block force pushes / Restrict deletions
6. 核对第 3.3 节机制限制（无"禁止 PR 指向 main"开关——规则兜底已由审批限制实现）

- [ ] **Step 6: 验证 ruleset 已存在**

```bash
gh api "repos/dslsdzc/core/rulesets" --jq '.[] | {name, enforcement, target}' 2>&1 || echo "gh 不可用——网页版确认两个 ruleset 存在"
```
Expected: `main-only-maintainer`（evaluate）+ `develop-integration`（evaluate）或网页版可见。

- [ ] **Step 7: 观察 evaluate 期告警（至少一个 PR 周期）**

对照 spec §8：evaluate 模式下 GitHub 会报告"本可拦截的事件"——确认无意外误报后转 active（网页版 Edit → Enforcement: Active）。转 active 前完成 Task 8（签名密钥），否则未签名提交会被真实拦截。

### Task 8: GitHub SSH 签名密钥注册（网页版，用户执行）

**Files:** 无（GitHub 设置）

**Interfaces:**
- Consumes: Task 2 的 `~/.ssh/id_ed25519.pub`
- Produces: 签名校验通过的前提——Task 9 验证

- [ ] **Step 1: 网页版注册 Signing key**

操作路径（gh 故障期，必须手动）：
1. GitHub → Settings → **SSH and GPG keys**
2. **New SSH key** → Key type: **Signing Key**（不是 Authentication）
3. Title: `core-signing`；Key 内容：`cat /home/DslsDZC/.ssh/id_ed25519.pub` 的输出（全粘贴）
4. Add SSH key

- [ ] **Step 2: 验证签名可被 GitHub 识别**

推送一个已签名提交（如 Task 3-7 的任一提交）到 feature 分支后，在 PR 页或 Commits 页查看提交：
Expected: 显示 **Verified** 徽标。若显示 "Unverified"，检查 Key type 是否误选为 Authentication Key，重新注册。

### Task 9: 端到端验证（spec §8 清单执行）

**Files:** 无（验证）

**Interfaces:**
- Consumes: Task 1-8 全部产物

- [ ] **Step 1: 本地安全网验证**

```bash
jj config get bookmarks.main.protect          # true
jj config get signing.sign-all                # true
# hook 拦截（喂 JSON 模拟）
echo '{"tool_input": {"command": "git log"}}' | python3 .claude/hooks/block-git.py; echo "exit=$?"   # exit=2
grep -c 'Bash(git' .claude/settings.local.json # 0
grep -n "版本控制流程" CLAUDE.md               # 存在
jj log -r @ --no-graph -T 'signature.format()'  # 非空（最新提交已签名）
```

- [ ] **Step 2: 分支与 ruleset 验证**

```bash
jj bookmark list develop                       # develop@origin 存在
jj log -r main@origin --no-graph -T 'commit_id.short()' && jj log -r develop@origin --no-graph -T 'commit_id.short()'  # develop 与 main 同点
```
网页版核对（ruleset active 后）：
- [ ] 直推 main 被拒（403）——仅 DslsDZC 且绕过关闭
- [ ] 指向 main 的 PR（非你创建）无法被批准合入
- [ ] develop→main 合并只有你执行成功
- [ ] RhineIris fork PR：base=develop，你审批后合入 develop
- [ ] PR 层 CI 绿（CI / check、CI / bootstrap-tests、CI / selfhost-tests）
- [ ] merge queue：审批过 + CI 绿 → 自动 squash 合入 develop → 源分支自动删除

- [ ] **Step 3: 首个治理 PR**

本 feature 分支 `feature/repo-governance` 即首个 PR：
1. 网页版 https://github.com/dslsdzc/core/pull/new/feature/repo-governance → base 选 **develop**（若 develop 尚未建则先建）
2. 按 PR 模板填写（变更描述/测试/语义保鲜影响）
3. 合并：你批准 → merge queue → squash 合入 develop
4. 之后按 §7 工作流执行一次完整的 feature → develop 流程，再执行一次 develop → main

- [ ] **Step 4: 收尾核对 spec §12 状态清单**

全部 ⬜ 项变为 ✅（本地配置、develop、ruleset、签名密钥、首个 PR）。剩余 ⬜（CI 完整层点亮、opt-regress）属后续项，在 spec §11 跟踪。

---

## Self-Review 记录

- **Spec 覆盖**：§3.1 M1-M7 → Task 7（main ruleset：update 规则= M1、非强推= M2、deletion= M3、pull_request 门槛= M4、required_signatures= M5、bypass_actors 空集= M6、protected tags 在网页版规则项= M7——M7 为 tag ruleset，脚本未含，已列入网页版 Step 5 核对）；§3.2 D1-D11 → Task 7（pull_request= D1/D3/D4/D5、required_status_checks= D6/D10、merge_queue= D8、squash+删分支= D9、D2= non_fast_forward、D7 文件路径限制为 ruleset 扩展规则（file_path_restriction），脚本未含——列入网页版核对项；D11= bypass_actors 空集）；§4 双路径 → Task 7 Step 5；§6 本地配置 → Task 1/2/3/4/5；§7 工作流 → Task 5/9；§8 验证清单 → Task 9；§9 四件套已随 spec 首 PR 提交（非本计划任务）；§10 发布规范 → 后续（非本计划）。
- **占位符扫描**：无 TBD/TODO；网页版核对项均给出精确勾选内容与 JSON 对照。
- **类型一致性**：CI job 名（CI / check 等）与 .github/workflows/ci.yml 的 job name 一致；signing 配置项名与 jj 0.44 实测一致（`config set --user/--repo`、`config get <NAME>` 已实测）。
