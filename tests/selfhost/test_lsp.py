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

if __name__ == "__main__":
    test_lifecycle()
    test_jsonrpc_error_codes()
    test_diagnostics_and_reset()
    print("lsp lifecycle: ALL PASS")
