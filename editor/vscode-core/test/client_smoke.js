// client_smoke.js — 扩展客户端端到端冒烟测试（无头）。
//
// 用 mock 的 vscode API 加载真实 client/extension.js，spawn 真实 build/corelsp，
// 验证：握手 → didOpen 全量同步 → publishDiagnostics → hover 请求响应。
//
// 运行（仓库根）：
//   node editor/vscode-core/test/client_smoke.js
//
// 退出码 0 = 通过；任何断言失败 → 非 0 并打印失败点。

const assert = require('assert');
const { EventEmitter } = require('events');

// ── mock vscode API ───────────────────────────────────────────────

class Uri {
  constructor(s) {
    this.s = s;
    this.fsPath = s.startsWith('file://') ? s.slice('file://'.length) : s;
  }
  toString() { return this.s; }
}
class Range {
  constructor(sl, sc, el, ec) { this.start = { line: sl, character: sc }; this.end = { line: el, character: ec }; }
}
class Diag { constructor(range, message, severity) { this.range = range; this.message = message; this.severity = severity; } }
class Hover { constructor(c) { this.contents = c; } }
class MarkdownString { constructor(v) { this.value = v; } }
class Location { constructor(uri, range) { this.uri = uri; this.range = range; } }
class CompletionItem { constructor(label) { this.label = label; } }
class DocumentSymbol { constructor(name, detail, kind, range, sel) { this.name = name; this.detail = detail; this.kind = kind; this.range = range; this.selectionRange = sel; } }
class SemanticTokens { constructor(data) { this.data = data; } }
class SemanticTokensBuilder {
  constructor() { this.all = []; }
  push(l, c, len, t, m) { this.all.push([l, c, len, t, m]); }
  build() { return new SemanticTokens(this.all); }
}

const emitters = {
  open: new EventEmitter(), change: new EventEmitter(),
  save: new EventEmitter(), close: new EventEmitter(),
};
const registered = { hover: null, def: null, completion: null, symbol: null, semtok: null };
const diagCollection = { set(uri, items) { diagCollection.uri = uri.toString(); diagCollection.items = items; }, delete() {} };
const outputLines = [];

const REPO_ROOT = require('path').join(__dirname, '..', '..', '..'); // editor/vscode-core/test → 仓库根

const mockVscode = {
  Uri: { parse: (s) => new Uri(s) },
  Range, Diagnostic: Diag, Hover, MarkdownString, Location,
  CompletionItem, DocumentSymbol, SemanticTokens, SemanticTokensBuilder,
  DiagnosticSeverity: { Error: 1, Warning: 2, Information: 3 },
  CompletionItemKind: { Text: 0, Function: 3, Keyword: 14, Variable: 6, Struct: 22, Enum: 23 },
  SymbolKind: { Variable: 13 },
  workspace: {
    getConfiguration: () => ({ get: (k, d) => d }), // 默认 build/corelsp + enabled
    workspaceFolders: [{ uri: new Uri('file://' + REPO_ROOT) }],
    textDocuments: [],
    onDidOpenTextDocument: (f) => { emitters.open.on('e', f); },
    onDidChangeTextDocument: (f) => { emitters.change.on('e', f); },
    onDidSaveTextDocument: (f) => { emitters.save.on('e', f); },
    onDidCloseTextDocument: (f) => { emitters.close.on('e', f); },
  },
  window: {
    createOutputChannel: () => ({ append: (s) => outputLines.push(s), appendLine: (s) => outputLines.push(s + '\n') }),
    showWarningMessage: (m) => { console.log('[warn]', m); },
    showErrorMessage: (m) => { console.log('[error]', m); },
  },
  languages: {
    createDiagnosticCollection: () => diagCollection,
    registerHoverProvider: (_sel, p) => { registered.hover = p; },
    registerDefinitionProvider: (_sel, p) => { registered.def = p; },
    registerCompletionItemProvider: (_sel, p) => { registered.completion = p; },
    registerDocumentSymbolProvider: (_sel, p) => { registered.symbol = p; },
    registerDocumentSemanticTokensProvider: (_sel, p) => { registered.semtok = p; },
  },
};

const Module = require('module');
const origLoad = Module._load;
Module._load = function (request, parent, isMain) {
  if (request === 'vscode') { return mockVscode; }
  return origLoad.call(this, request, parent, isMain);
};

// ── 测试主体 ──────────────────────────────────────────────────────

const SRC = 'fn main() -> int {\n    return 42;\n}\n';
const doc = {
  uri: new Uri('file:///proj/main.cr'),
  languageId: 'core', version: 1,
  getText: () => SRC,
};
const fakeDocParam = () => doc;

function requestTest() {
  const ext = require('../client/extension.js');
  return ext.activate({ subscriptions: [] }).then(() => {
    // didOpen → 服务器应回 publishDiagnostics（无诊断 → 空数组也要回）
    emitters.open.emit('e', doc);
    return new Promise((resolve) => setTimeout(resolve, 1500));
  });
}

async function main() {
  await requestTest();

  // 1) 诊断：didOpen 后收到 publishDiagnostics（main.cr 无错误 → 空数组）
  assert(diagCollection.uri === 'file:///proj/main.cr',
    `诊断应发布到 main.cr，实际 ${diagCollection.uri}`);
  assert(Array.isArray(diagCollection.items), '诊断应为数组');
  assert(diagCollection.items.length === 0,
    `main.cr 应无诊断，实际 ${JSON.stringify(diagCollection.items)}`);

  // 2) 语法错误 → 一条错误诊断
  diagCollection.items = null;
  const badDoc = { ...doc, getText: () => 'fn main() -> int { return ; }\n' };
  emitters.open.emit('e', badDoc);
  await new Promise((r) => setTimeout(r, 1500));
  assert(diagCollection.items && diagCollection.items.length > 0,
    '坏代码应产生诊断');
  assert(diagCollection.items[0].severity === 1, '诊断 severity 应为 Error');

  // 3) hover：对 "main" 标识符请求 → 非空 contents
  emitters.open.emit('e', doc); // 恢复好文档（服务器快照重建）
  await new Promise((r) => setTimeout(r, 1200));
  const h = await registered.hover.provideHover(doc, { line: 0, character: 3 });
  assert(h && h.contents && String(h.contents.value || h.contents).length > 0,
    'hover 应返回内容');

  // 4) semanticTokens：好文档 → data 非空，且首令牌在 0 行（main 关键字）
  const st = await registered.semtok.provideDocumentSemanticTokens(doc);
  assert(st && st.data && st.data.length > 0, 'semanticTokens 应有令牌');
  const first = st.data[0];
  assert(first[0] === 0 && first[1] === 0, `首令牌应位于 0 行 0 列，实际 ${first[0]}:${first[1]}`);

  // 5) documentSymbol：main 函数应出现在大纲
  const syms = await registered.symbol.provideDocumentSymbols(doc);
  assert(Array.isArray(syms) && syms.some((s) => s.name === 'main'),
    'documentSymbol 应包含 main');

  // 6) completion：@ 位置 → items
  const c = await registered.completion.provideCompletionItems(doc, { line: 1, character: 4 }, '@');
  assert(Array.isArray(c), 'completion 应为数组');

  console.log('client_smoke: 全部通过（握手/诊断/hover/semanticTokens/documentSymbol/completion）');
  process.exit(0);
}

main().catch((e) => { console.error('FAIL:', e.message); process.exit(1); });
