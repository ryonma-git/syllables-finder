#!/bin/sh
# Open the extracted static worksheet folder to browsers on the facilitator's LAN.
cd "$(dirname "$0")" || exit 1
exec /usr/bin/env python3 - "$@" <<'PY'
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import socket
import sys
from urllib.parse import urlsplit

root = Path.cwd()
if (root / "dist" / "index.html").is_file():
    root = root / "dist"
types = {"index.html": "text/html; charset=utf-8", "style.css": "text/css; charset=utf-8",
         "CMUdict-LICENSE.txt": "text/plain; charset=utf-8"}
for asset in ("dictionary", "engine", "worksheet", "openai", "app"):
    types[asset + ".js"] = "text/javascript; charset=utf-8"
if any(not (root / name).is_file() for name in types):
    sys.exit("Web版をフォルダごと展開してから起動してください。")

class WorksheetServer(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        name = "index.html" if path == "/" else path[1:]
        if name not in types:
            self.send_error(404)
            return
        data = (root / name).read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", types[name])
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass

with ThreadingHTTPServer(("", 0), WorksheetServer) as server:
    with closing(socket.socket(socket.AF_INET, socket.SOCK_DGRAM)) as sock:
        try:
            sock.connect(("192.0.2.1", 9))
            address = sock.getsockname()[0]
        except OSError:
            address = socket.gethostname() + ".local"
    print("同じWi-Fiに接続した参加者が開くURL", flush=True)
    print(f"http://{address}:{server.server_port}/", flush=True)
    print("終了するには、このウインドウで Control + C を押してください。", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
PY
