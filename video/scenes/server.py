#!/usr/bin/env python3
"""Serve the story scenes on 127.0.0.1:5181 for the recording.

POST /adopt runs tools/adopt-fragment.py for the demo's CORS Fragment against the real Dashboard and
streams its output, so the adoption scene shows the tool's actual run. It needs TYK_DASHBOARD_KEY
in the environment; the key is passed to the tool and never sent to the browser.
"""
import http.server
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(os.path.dirname(os.path.dirname(HERE)), "tools", "adopt-fragment.py")
COMMAND = [sys.executable, "-u", TOOL, "--fragment", "cors-browser-apps", "--path", "x-tyk-api-gateway.middleware.global.cors"]


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=HERE, **kw)

    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"scenes")
            return
        super().do_GET()

    def do_POST(self):
        if self.path != "/adopt":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        with subprocess.Popen(COMMAND, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as proc:
            for line in proc.stdout:
                self.wfile.write(line)
                self.wfile.flush()


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("127.0.0.1", 5181), Handler).serve_forever()
