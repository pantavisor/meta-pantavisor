#!/usr/bin/env python3
"""
Agentic camera-analyzer

1. Connects to camera-feed via the injected xconnect UDS at
   /run/pv/services/camera-feed.sock and consumes NDJSON image frames.
2. Runs a (stubbed) object-detection + OCR pass per frame. Replace
   `analyze_frame` with a real model (tflite, onnxruntime, paddleocr,
   whatever fits the SoC).
3. Re-publishes analysis results as NDJSON on its own UDS so any number
   of downstream subscribers can stream them.
"""

import base64
import hashlib
import json
import os
import random
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

FEED_SOCKET = "/run/pv/services/camera-feed.sock"
FEED_PATH = "/subscribe"

_subscribers_lock = threading.Lock()
_subscribers = []


# ---------------------------------------------------------------------------
# Analysis (stub)
# ---------------------------------------------------------------------------

MOCK_LABELS = ["person", "cat", "dog", "car", "cup", "laptop", "book"]
MOCK_WORDS = ["HELLO", "PANTAVISOR", "EDGE", "AGENTIC", "2026"]


def analyze_frame(frame: dict) -> dict:
    """
    Pretend to run object detection + OCR on the frame payload. We seed
    RNG from the frame data so the mock output is deterministic per frame.
    """
    raw = base64.b64decode(frame["data"])
    digest = hashlib.md5(raw).hexdigest()
    rng = random.Random(int(digest[:8], 16))

    # Not every feed advertises dimensions (e.g. the mock feed ships
    # bare JPEG/PNG blobs). Fall back to a notional canvas for bbox
    # coordinates — a real model would get these from the decoded
    # image instead.
    width = int(frame.get("width") or 640)
    height = int(frame.get("height") or 480)

    num_objects = rng.randint(0, 3)
    objects = []
    for _ in range(num_objects):
        objects.append({
            "label": rng.choice(MOCK_LABELS),
            "confidence": round(rng.uniform(0.5, 0.99), 3),
            "bbox": [
                rng.randint(0, width // 2),
                rng.randint(0, height // 2),
                rng.randint(width // 2, width),
                rng.randint(height // 2, height),
            ],
        })

    ocr_text = " ".join(rng.sample(MOCK_WORDS, rng.randint(0, 2)))

    return {
        "frame_id": frame.get("frame_id"),
        "ts_frame": frame.get("ts"),
        "ts_analyzed": time.time(),
        "frame_digest": digest,
        "objects": objects,
        "ocr": ocr_text,
    }


# ---------------------------------------------------------------------------
# Feed consumer
# ---------------------------------------------------------------------------

def _read_http_chunked_lines(sock):
    """
    Yield decoded NDJSON lines from an HTTP chunked response body on a
    connected unix socket. We do the bare minimum — parse status line,
    skip headers, then read chunk-length / chunk-data pairs and split on
    newlines.
    """
    buf = b""

    def readline():
        nonlocal buf
        while b"\r\n" not in buf:
            more = sock.recv(4096)
            if not more:
                return None
            buf += more
        line, buf = buf.split(b"\r\n", 1)
        return line

    def readexact(n):
        nonlocal buf
        while len(buf) < n:
            more = sock.recv(max(4096, n - len(buf)))
            if not more:
                return None
            buf += more
        chunk, buf = buf[:n], buf[n:]
        return chunk

    status = readline()
    if not status or b"200" not in status:
        raise RuntimeError(f"feed handshake failed: {status!r}")
    while True:
        hdr = readline()
        if hdr == b"" or hdr is None:
            break

    pending = b""
    while True:
        size_line = readline()
        if size_line is None:
            return
        size = int(size_line.split(b";", 1)[0], 16)
        if size == 0:
            return
        data = readexact(size)
        if data is None:
            return
        # Trailing CRLF after chunk data
        readexact(2)
        pending += data
        while b"\n" in pending:
            line, pending = pending.split(b"\n", 1)
            line = line.strip()
            if line:
                yield line.decode("utf-8", errors="replace")


def consumer_loop():
    backoff = 1.0
    while True:
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(FEED_SOCKET)
            req = (
                f"GET {FEED_PATH} HTTP/1.1\r\n"
                f"Host: camera-feed\r\n"
                f"Accept: application/x-ndjson\r\n"
                f"Connection: keep-alive\r\n\r\n"
            ).encode()
            sock.sendall(req)
            print(f"analyzer: subscribed to {FEED_SOCKET}{FEED_PATH}", flush=True)
            backoff = 1.0
            for line in _read_http_chunked_lines(sock):
                try:
                    frame = json.loads(line)
                except json.JSONDecodeError:
                    continue
                result = analyze_frame(frame)
                _broadcast(result)
        except Exception as e:
            print(f"analyzer: feed connection lost: {e!r}", flush=True)
            time.sleep(backoff)
            backoff = min(backoff * 2, 15.0)
        finally:
            try:
                sock.close()
            except Exception:
                pass


def _broadcast(result: dict):
    line = (json.dumps(result) + "\n").encode()
    with _subscribers_lock:
        dead = []
        for entry in _subscribers:
            wfile, alive = entry
            try:
                wfile.write(f"{len(line):x}\r\n".encode())
                wfile.write(line)
                wfile.write(b"\r\n")
                wfile.flush()
            except Exception:
                alive[0] = False
                dead.append(entry)
        for entry in dead:
            _subscribers.remove(entry)


# ---------------------------------------------------------------------------
# Publish side (same NDJSON-over-chunked pattern as camera-feed)
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    def address_string(self):
        return "uds"

    def log_message(self, fmt, *args):
        sys.stderr.write("camera-analyzer: " + (fmt % args) + "\n")

    def do_GET(self):
        if self.path == "/info":
            body = json.dumps({
                "service": "camera-analysis",
                "upstream_feed": FEED_SOCKET,
            }).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if self.path == "/subscribe":
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson")
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            alive = [True]
            entry = (self.wfile, alive)
            with _subscribers_lock:
                _subscribers.append(entry)
            self.log_message("analysis subscriber joined (total=%d)", len(_subscribers))
            while alive[0]:
                time.sleep(0.5)
            return

        self.send_response(404)
        self.end_headers()


class UnixHTTPServer(HTTPServer):
    def server_bind(self):
        self.socket.bind(self.server_address)
        self.server_address = self.socket.getsockname()


class ThreadedUnixHTTPServer(UnixHTTPServer):
    daemon_threads = True

    def process_request(self, request, client_address):
        t = threading.Thread(
            target=self.process_request_thread, args=(request, client_address)
        )
        t.daemon = True
        t.start()

    def process_request_thread(self, request, client_address):
        try:
            self.finish_request(request, client_address)
        finally:
            self.shutdown_request(request)


def run(socket_path: str):
    if os.path.exists(socket_path):
        os.remove(socket_path)
    os.makedirs(os.path.dirname(socket_path), exist_ok=True)

    httpd = ThreadedUnixHTTPServer(socket_path, Handler, bind_and_activate=False)
    httpd.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    httpd.server_bind()
    httpd.server_activate()

    threading.Thread(target=consumer_loop, daemon=True).start()
    print(f"camera-analyzer publishing on {socket_path}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "/run/camera/analysis.sock"
    run(path)
