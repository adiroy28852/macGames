"""Evaluate JavaScript in the Steam client's UI through Chromium's DevTools port.

Steam opens the port (localhost:8080) when its install folder contains
.cef-enable-remote-debugging. Used by `macgames unlock` to leave Family View
without clicking through the UI.

usage: steam-cdp.py '<javascript>'   (prints the result as JSON)
"""
import base64, json, os, socket, struct, sys, urllib.request

PORT = 8080
TARGET = "SharedJSContext"


def ws_connect(url):
    host_port, path = url[len("ws://"):].split("/", 1)
    host, port = host_port.split(":")
    s = socket.create_connection((host, int(port)), timeout=30)
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall((f"GET /{path} HTTP/1.1\r\nHost: {host_port}\r\nUpgrade: websocket\r\n"
               f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
               "Sec-WebSocket-Version: 13\r\n\r\n").encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += s.recv(4096)
    if b" 101 " not in resp.split(b"\r\n", 1)[0]:
        raise SystemExit(f"websocket handshake failed: {resp[:80]!r}")
    return s


def ws_send(s, text):
    data = text.encode()
    mask = os.urandom(4)
    n = len(data)
    head = bytes([0x81]) + (bytes([0x80 | n]) if n < 126 else bytes([0x80 | 126]) + struct.pack(">H", n))
    s.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))


def ws_recv(s):
    def read(n):
        buf = b""
        while len(buf) < n:
            chunk = s.recv(n - len(buf))
            if not chunk:
                raise SystemExit("connection closed")
            buf += chunk
        return buf
    msg = b""
    while True:
        b0, b1 = read(2)
        n = b1 & 0x7F
        if n == 126:
            n, = struct.unpack(">H", read(2))
        elif n == 127:
            n, = struct.unpack(">Q", read(8))
        msg += read(n)
        if b0 & 0x80:
            return msg.decode()


def main():
    targets = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json", timeout=5))
    target = next((t for t in targets if t.get("title") == TARGET), None)
    if not target:
        raise SystemExit(f"no '{TARGET}' page; titles: {[t.get('title') for t in targets]}")
    s = ws_connect(target["webSocketDebuggerUrl"])
    ws_send(s, json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {
        "expression": sys.argv[1], "awaitPromise": True, "returnByValue": True}}))
    while True:
        reply = json.loads(ws_recv(s))
        if reply.get("id") == 1:
            break
    result = reply.get("result", {})
    if "exceptionDetails" in result:
        raise SystemExit(json.dumps(result["exceptionDetails"]))
    print(json.dumps(result.get("result", {}).get("value")))


if __name__ == "__main__":
    main()
