#!/usr/bin/env python3
"""
Agentic camera-stream

Serves a small HTML+JS dashboard on TCP (default :8080) that streams the
NDJSON output of camera-analyzer to the browser. The /stream endpoint is
a chunked proxy over the xconnect-injected UDS to
/run/pv/services/camera-analysis.sock.
"""

import os
import socket
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ANALYSIS_SOCKET = "/run/pv/services/camera-analysis.sock"
ANALYSIS_PATH = "/subscribe"
INDEX_PATH = "/usr/share/agentic-camera-stream/index.html"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("camera-stream: " + (fmt % args) + "\n")

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            try:
                with open(INDEX_PATH, "rb") as f:
                    body = f.read()
            except OSError:
                body = b"<h1>index.html missing</h1>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if self.path == "/stream":
            self._proxy_stream()
            return

        self.send_response(404)
        self.end_headers()

    def _proxy_stream(self):
        try:
            up = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            up.connect(ANALYSIS_SOCKET)
        except OSError as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(f"cannot reach analyzer: {e}".encode())
            return

        req = (
            f"GET {ANALYSIS_PATH} HTTP/1.1\r\n"
            f"Host: camera-analysis\r\n"
            f"Accept: application/x-ndjson\r\n"
            f"Connection: keep-alive\r\n\r\n"
        ).encode()
        try:
            up.sendall(req)
        except OSError:
            up.close()
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        buf = b""

        def readline():
            nonlocal buf
            while b"\r\n" not in buf:
                more = up.recv(4096)
                if not more:
                    return None
                buf += more
            line, buf = buf.split(b"\r\n", 1)
            return line

        def readexact(n):
            nonlocal buf
            while len(buf) < n:
                more = up.recv(max(4096, n - len(buf)))
                if not more:
                    return None
                buf += more
            chunk, buf = buf[:n], buf[n:]
            return chunk

        status = readline()
        if not status or b"200" not in status:
            up.close()
            return
        while True:
            hdr = readline()
            if hdr == b"" or hdr is None:
                break

        try:
            while True:
                size_line = readline()
                if size_line is None:
                    break
                size = int(size_line.split(b";", 1)[0], 16)
                if size == 0:
                    break
                data = readexact(size)
                if data is None:
                    break
                readexact(2)
                # Re-emit as chunked to the browser.
                self.wfile.write(f"{len(data):x}\r\n".encode())
                self.wfile.write(data)
                self.wfile.write(b"\r\n")
                self.wfile.flush()
        except (OSError, ConnectionError):
            pass
        finally:
            try:
                self.wfile.write(b"0\r\n\r\n")
            except Exception:
                pass
            up.close()


def run(port: int):
    httpd = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    httpd.daemon_threads = True
    print(f"camera-stream UI on http://0.0.0.0:{port}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    run(port)
