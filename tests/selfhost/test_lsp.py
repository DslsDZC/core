import json, subprocess, sys, time

BIN = "build/corelsp"

def read_frame(proc) -> dict:
    headers = {}
    while True:
        line = proc.stdout.readline()
        if line in (b"\r\n", b"\n"):
            break
        k, _, v = line.decode().partition(":")
        headers[k.strip().lower()] = v.strip()
    if "content-length" not in headers:
        return None
    return json.loads(proc.stdout.read(int(headers["content-length"])))

def send(proc, msg: dict) -> dict:
    body = json.dumps(msg).encode()
    proc.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
    proc.stdin.flush()
    return read_frame(proc)

def test_lifecycle():
    proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    r = send(proc, {"jsonrpc": "2.0", "id": 1, "method": "initialize",
                    "params": {"capabilities": {}}})
    assert r["result"]["capabilities"]["textDocumentSync"] == 1, r
    send(proc, {"jsonrpc": "2.0", "method": "initialized", "params": {}})
    r = send(proc, {"jsonrpc": "2.0", "id": 2, "method": "bogus/method"})
    assert r["error"]["code"] == -32601, r
    r = send(proc, {"jsonrpc": "2.0", "id": 3, "method": "shutdown"})
    assert r["result"] is None
    proc.stdin.close()
    assert proc.wait(timeout=5) == 0

def test_jsonrpc_error_codes():
    proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    # initialize 前发普通请求 → -32602
    r = send(proc, {"jsonrpc": "2.0", "id": 9, "method": "hover", "params": {}})
    assert r["error"]["code"] == -32602, r
    send(proc, {"jsonrpc": "2.0", "id": 10, "method": "initialize", "params": {}})
    r = send(proc, {"jsonrpc": "2.0", "id": 11, "method": "shutdown"})
    proc.stdin.close(); proc.wait(timeout=5)

SAMPLE = 'fn main() -> int { return 42; }'
BAD = 'fn main() -> int { return ; }'

def test_diagnostics_and_reset():
    proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    send(proc, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
    uri = "file:///tmp/test_sample.cr"
    def open_doc(text):
        # 注意：不能用 send()——它自带 read_frame，会吞掉 publishDiagnostics 帧；
        # 直接写帧再读一帧（didOpen 是通知，服务器只回 publishDiagnostics 通知）
        body = json.dumps({"jsonrpc": "2.0", "method": "textDocument/didOpen",
                           "params": {"textDocument": {"uri": uri, "version": 1,
                                                       "text": text}}}).encode()
        proc.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
        proc.stdin.flush()
        return read_frame(proc)
    r = open_doc(SAMPLE)
    assert r is not None and r["method"] == "textDocument/publishDiagnostics", r
    assert r["params"]["diagnostics"] == [], r
    # 重置回归：改坏 → 诊断必须更新（抓幽灵诊断）
    r = open_doc(BAD)
    assert r["params"]["diagnostics"] != [], r
    send(proc, {"jsonrpc": "2.0", "id": 9, "method": "shutdown"})
    proc.stdin.close(); proc.wait(timeout=5)

def test_hover_and_definition():
    proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    send(proc, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
    uri = "file:///tmp/hover_test.cr"
    #       0: fn add(a: int, b: int) -> int {
    #       1:     return a + b;
    #       2: }
    #       3: (空行)
    #       4: fn main() -> int {
    #       5:     x := add(1, 2);
    #       6:     return x;
    #       7: }
    src = "fn add(a: int, b: int) -> int {\n    return a + b;\n}\n\nfn main() -> int {\n    x := add(1, 2);\n    return x;\n}\n"
    # 注意：didOpen 不能用 send()——它自带 read_frame 会吞掉 publishDiagnostics
    # 帧（brief 原文 send()+read_frame() 双读会永久阻塞）；直接写帧再读一帧。
    body = json.dumps({"jsonrpc": "2.0", "method": "textDocument/didOpen",
                       "params": {"textDocument": {"uri": uri, "version": 1,
                                                   "text": src}}}).encode()
    proc.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
    proc.stdin.flush()
    read_frame(proc)  # 丢弃 publishDiagnostics 通知
    # hover 在 add 调用处（0-based line=5, character=10 即 add 起点）
    r = send(proc, {"jsonrpc": "2.0", "id": 2, "method": "textDocument/hover",
                    "params": {"textDocument": {"uri": uri},
                               "position": {"line": 5, "character": 10}}})
    assert "fn add" in r["result"]["contents"], r
    # definition 同位置 → 声明在 line 0
    r = send(proc, {"jsonrpc": "2.0", "id": 3, "method": "textDocument/definition",
                    "params": {"textDocument": {"uri": uri},
                               "position": {"line": 5, "character": 10}}})
    assert r["result"]["uri"] == uri, r
    assert r["result"]["range"]["start"]["line"] == 0, r
    send(proc, {"jsonrpc": "2.0", "id": 9, "method": "shutdown"})
    proc.stdin.close(); proc.wait(timeout=5)

def test_completion_and_document_symbol():
    proc = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    send(proc, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
    uri = "file:///tmp/symbols_test.cr"
    #       0: fn add(a: int, b: int) -> int {
    #       1:     return a + b;
    #       2: }
    #       3: (空行)
    #       4: struct Point { x: int, y: int }
    #       5: (空行)
    #       6: enum Color { Red, Green, Blue }
    #       7: (空行)
    #       8: fn main() -> int {
    #       9:     poi := add(1, 2);
    #      10:     return @sizeOf(int);
    #      11: }
    src = ("fn add(a: int, b: int) -> int {\n    return a + b;\n}\n\n"
           "struct Point { x: int, y: int }\n\n"
           "enum Color { Red, Green, Blue }\n\n"
           "fn main() -> int {\n    poi := add(1, 2);\n    return @sizeOf(int);\n}\n")
    body = json.dumps({"jsonrpc": "2.0", "method": "textDocument/didOpen",
                       "params": {"textDocument": {"uri": uri, "version": 1,
                                                   "text": src}}}).encode()
    proc.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
    proc.stdin.flush()
    read_frame(proc)  # 丢弃 publishDiagnostics 通知
    # completion 在空行（line 3）→ 全候选：关键字 + 已声明符号
    r = send(proc, {"jsonrpc": "2.0", "id": 2, "method": "textDocument/completion",
                    "params": {"textDocument": {"uri": uri},
                               "position": {"line": 3, "character": 0},
                               "context": {"triggerKind": 1}}})
    assert "error" not in r, r
    labels = {it["label"]: it["kind"] for it in r["result"]["items"]}
    assert labels["fn"] == 14, r
    assert labels["add"] == 3 and labels["main"] == 3, r
    assert labels["Point"] == 23 and labels["Color"] == 23, r
    # 符号候选前缀过滤（大小写不敏感）：line 9 的 "po"（character 6）→ 仅 Point
    r = send(proc, {"jsonrpc": "2.0", "id": 3, "method": "textDocument/completion",
                    "params": {"textDocument": {"uri": uri},
                               "position": {"line": 9, "character": 6},
                               "context": {"triggerKind": 1}}})
    assert "error" not in r, r
    labels = [it["label"] for it in r["result"]["items"]]
    assert labels == ["Point"], r
    # 关键字前缀过滤："fn" 只匹配关键字 fn（无符号以 fn 开头）
    r = send(proc, {"jsonrpc": "2.0", "id": 4, "method": "textDocument/completion",
                    "params": {"textDocument": {"uri": uri},
                               "position": {"line": 8, "character": 2},
                               "context": {"triggerKind": 1}}})
    assert "error" not in r, r
    labels = [it["label"] for it in r["result"]["items"]]
    assert labels == ["fn"], r
    # completion 在 "@size" 后（line 10，character 16）→ @ 内建过滤
    r = send(proc, {"jsonrpc": "2.0", "id": 5, "method": "textDocument/completion",
                    "params": {"textDocument": {"uri": uri},
                               "position": {"line": 10, "character": 16},
                               "context": {"triggerKind": 1}}})
    assert "error" not in r, r
    assert [it["label"] for it in r["result"]["items"]] == ["sizeOf"], r
    # documentSymbol → 顶层 4 个符号，源顺序 + kind
    r = send(proc, {"jsonrpc": "2.0", "id": 6, "method": "textDocument/documentSymbol",
                    "params": {"textDocument": {"uri": uri}}})
    assert "error" not in r, r
    syms = r["result"]
    assert [s["name"] for s in syms] == ["add", "Point", "Color", "main"], r
    kinds = {s["name"]: s["kind"] for s in syms}
    assert kinds["add"] == 12 and kinds["main"] == 12, r
    assert kinds["Point"] == 23 and kinds["Color"] == 23, r
    send(proc, {"jsonrpc": "2.0", "id": 9, "method": "shutdown"})
    proc.stdin.close(); proc.wait(timeout=5)

if __name__ == "__main__":
    test_lifecycle()
    test_jsonrpc_error_codes()
    test_diagnostics_and_reset()
    test_hover_and_definition()
    test_completion_and_document_symbol()
    print("lsp lifecycle: ALL PASS")
