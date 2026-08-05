#!/usr/bin/env python3
"""HTTP shim for Corezoid Git Call's custom-Dockerfile contract.

Git Call expects the container to run an HTTP server on $GIT_CALL_PORT and
handle POST requests carrying a JSON-RPC 2.0 body. `asan_identity_gate`
(compiled from Main.lean) already speaks JSON-RPC 2.0, but over stdin/stdout
as a one-shot process per invocation — this shim is the thinnest possible
bridge between the two: one HTTP POST in, one subprocess call out, its stdout
line back as the HTTP response body. No JSON-RPC logic lives here; it only
forwards bytes.
"""
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BINARY = os.environ.get("GATE_BINARY", "/app/.lake/build/bin/asan_identity_gate")


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        proc = subprocess.run(
            [BINARY],
            input=body + b"\n",
            capture_output=True,
            timeout=10,
        )
        response_line = proc.stdout.decode("utf-8", errors="replace").strip()

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(response_line.encode("utf-8"))

    def log_message(self, format, *args):
        pass  # keep container logs to what Corezoid actually needs


if __name__ == "__main__":
    port = int(os.environ["GIT_CALL_PORT"])
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
