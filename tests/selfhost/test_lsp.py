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

if __name__ == "__main__":
    test_lifecycle()
    test_jsonrpc_error_codes()
    print("lsp lifecycle: ALL PASS")
