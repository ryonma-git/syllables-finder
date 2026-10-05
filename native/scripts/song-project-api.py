#!/usr/bin/env python3
"""Loopback-only JSON API for turning supplied lyrics into Singing Workspace files."""

import argparse
import json
import re
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_BODY = 200_000


def output_name(payload):
    requested = payload.get("fileName")
    if requested is None:
        title = payload.get("title", "")
        if not isinstance(title, str):
            raise ValueError("titleは文字列にしてください。")
        stem = re.sub(r"[^A-Za-z0-9]+", "-", title).strip("-")[:100] or "song"
        requested = stem + ".songproj"
    if (
        not isinstance(requested, str)
        or len(requested) > 120
        or not requested.endswith(".songproj")
        or requested.startswith(".")
        or "/" in requested
        or "\\" in requested
        or ".." in requested
        or any(ord(char) < 32 for char in requested)
    ):
        raise ValueError("fileNameはフォルダ名を含まない .songproj 名にしてください。")
    return requested


def make_handler(tool, output_dir, model):
    class Handler(BaseHTTPRequestHandler):
        def reply(self, status, data):
            encoded = json.dumps(data, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

        def do_GET(self):
            if self.path != "/health":
                return self.reply(404, {"error": "not found"})
            return self.reply(200, {"status": "ok", "outputDirectory": str(output_dir),
                                    "localModel": model})

        def do_POST(self):
            if self.path != "/v1/song-projects":
                return self.reply(404, {"error": "not found"})
            try:
                length = int(self.headers.get("Content-Length", ""))
                if not 0 < length <= MAX_BODY:
                    return self.reply(413, {"error": "入力JSONは200KB以内にしてください。"})
                raw = self.rfile.read(length)
                payload = json.loads(raw)
                if not isinstance(payload, dict):
                    raise ValueError("JSONオブジェクトが必要です。")
                target = output_dir / output_name(payload)
                if target.exists() or target.is_symlink():
                    return self.reply(409, {"error": "同名の曲ファイルがあります。上書きしません。"})
                command = [str(tool), "-", str(target)]
                if model:
                    command += ["--ollama", model]
                result = subprocess.run(command, input=raw, capture_output=True, timeout=3600)
                if result.returncode:
                    return self.reply(422, {"error": result.stderr.decode("utf-8", "replace").strip()[:500]})
                return self.reply(201, json.loads(result.stdout))
            except (ValueError, json.JSONDecodeError) as error:
                return self.reply(400, {"error": str(error)})
            except subprocess.TimeoutExpired:
                return self.reply(504, {"error": "ローカル生成の制限時間を超えました。"})

        def log_message(self, format_string, *args):
            # Never log the body: it may contain a personal song or classroom text.
            print("song-project-api", self.client_address[0], format_string % args, flush=True)

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--tool", type=Path, default=Path(__file__).resolve().parents[1] / ".build/debug/SongGenerateTool")
    parser.add_argument("--ollama-model", help="Optional local Ollama model for meaning and pronunciation candidates")
    args = parser.parse_args()
    if not args.output_dir.is_dir() or not args.tool.is_file():
        parser.error("保存先フォルダとビルド済みの SongGenerateTool が必要です。")
    if not 0 <= args.port <= 65535:
        parser.error("portは0〜65535にしてください。")
    with ThreadingHTTPServer(("127.0.0.1", args.port),
                             make_handler(args.tool.resolve(), args.output_dir.resolve(), args.ollama_model)) as server:
        print(f"http://127.0.0.1:{server.server_port}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
