# 编辑器 LSP 配置（corelsp）

corelsp 是 Core 语言的语言服务器（LSP 协议，stdio 管道），提供：

| 功能 | 触发方式 | 说明 |
|------|----------|------|
| 诊断 | 打开/编辑/保存时 | `textDocument/publishDiagnostics`，错误 + 行内定位 |
| 悬浮信息 | `hover` | 标识符类型/签名（基于快照） |
| 跳转定义 | `definition` | 函数/全局/类型声明位置 |
| 补全 | `completion`（`@` 触发） | 关键字 + 符号 + `@` 内建 |
| 文档符号 | `documentSymbol` | 函数/结构体/枚举大纲 |
| 语义令牌 | `semanticTokens/full` | keyword/type/function/variable/... 着色 |

**限制**：全量同步（`textDocumentSync=1`）；语义查询基于「最后一次成功检查的快照」——文档有语法错误时悬停/跳转可能返回空结果；服务器是单文档全局状态机，每次 `didOpen` 重新检查主文档。

## 构建服务器

```bash
python3 build_selfhost_native.py   # 产出 build/corelsp
```

## Neovim（内置 LSP，nvim 0.10+）

### 最简配置（需从项目根启动 nvim）

```lua
-- after/ftplugin/core.lua（或在 init.lua 中按文件类型 autocmd 调用）
vim.lsp.start({
  cmd = { 'build/corelsp' },
  name = 'corelsp',
})
```

### 健壮版（任意 cwd，自动定位项目根）

```lua
-- after/ftplugin/core.lua
-- 从当前文件目录向上查找包含 build/corelsp / Core.toml / .git 的项目根
local root = vim.fs.root(0, { 'build/corelsp', 'Core.toml', '.git' })
if not root then return end

vim.lsp.start({
  cmd = { root .. '/build/corelsp' },
  name = 'corelsp',
})

-- 常用键位（nvim 内置 LSP 默认键位按需自设）
vim.keymap.set('n', 'K', vim.lsp.buf.hover, { buffer = 0 })
vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { buffer = 0 })
```

### 说明

- **诊断**：nvim 自动接收 `publishDiagnostics` 并显示（`vim.diagnostic`），无需额外配置。
- **补全**：`vim.lsp.buf.completion`（`<C-x><C-o>`），或 blink.cmp / nvim-cmp 等补全框架自动接入 LSP source。服务器补全为 `@` 触发（`triggerCharacters: ["@"]`）。
- **语义着色**：nvim 0.10+ 语义令牌默认开启（不存在 `:SemanticTokensEnable` 命令，无需配置）；如需高亮，需 colorscheme 将 `@lsp.type.*` 链接到 `@keyword` 等高亮组。
- **与既有 compiler 插件互斥**：`editor/nvim/plugin/core.lua`（基于 `corec` 编译器的诊断/跳转）与 LSP 功能重叠——启用 LSP 时建议移除该插件，避免诊断与键位重复。
- 安装语法高亮/文件类型检测等基础配置见 `editor/README.md`。

## VS Code

扩展位于 `editor/vscode-core/`（语法高亮 + corelsp 客户端）：

```bash
code --install-extension editor/vscode-core/
```

- 服务器路径默认取工作区根目录下 `build/corelsp`，可用设置 `corelsp.path` 覆盖（绝对路径或相对工作区根）。
- 设置 `corelsp.enabled = false` 可关闭 LSP（仅保留语法高亮）。
- 从源码调试：VS Code 打开 `editor/vscode-core/` 按 F5（见 `.vscode/tasks.json`）。

## Zed（2026-08-28 接入）

`editor/zed/`（tree-sitter 语法）+ corelsp LSP。Zed 无需扩展。

**本仓库已内置项目配置**（`.zed/settings.json`，打开即用）——binary 相对路径以工作区根（仓库根）解析：

```json
{
  "lsp": {
    "corelsp": {
      "binary": { "path": "build/corelsp" }
    }
  },
  "languages": {
    "Core": {
      "language_servers": ["corelsp"],
      "file_types": ["cr"]
    }
  }
}
```

**其他项目/全局接入**：全局 `~/.config/zed/settings.json` 同上，`binary.path` 建议用 **绝对路径**（全局配置无工作区根可解析相对路径）。

- `languages.Core`：注册 Core 语言（Zed 内置无 `.cr` 映射）——`file_types` 把 `.cr` 归入该语言，`language_servers` 挂上 corelsp。
- 已通告能力（2026-08-28 补 `hoverProvider`/`definitionProvider` 通告）：诊断（全量同步）、悬浮、跳转定义、补全（`@` 触发）、文档符号、语义令牌。
- Zed 默认键位：`F12` 跳转定义；悬停即看；LSP 诊断自动显示。
- 构建 corelsp：`python3 build_selfhost_native.py`（产出 `build/corelsp`）。

## 其他编辑器

其余编辑器（Emacs/LSP-mode、Helix 等）：corelsp 为标准 stdio LSP 服务器，参照各自
[自定义语言服务器](https://zed.dev/docs/languages) 配置模式接入（要点：绝对路径 + `.cr` 文件类型注册 + language_servers 挂载）。
