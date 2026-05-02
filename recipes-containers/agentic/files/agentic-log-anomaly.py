#!/usr/bin/env python3
"""
Agentic log-anomaly classifier

Subscribes to the log-feed NDJSON stream, sends each ERROR event (plus its
surrounding context) to a local LLM (llama-server, OpenAI-compatible API),
and republishes the verdict as its own NDJSON feed.

DeepSeek endpoint resolution:
  - If DEEPSEEK_UDS is set (or /run/pv/services/deepseek-r1.sock exists),
    POST over HTTP-on-UDS.
  - Else fall back to DEEPSEEK_URL (default http://127.0.0.1:8080).

The model is asked for a strict JSON verdict:
  {"severity": "critical|warn|info|ignore", "warn": bool, "reason": "..."}
"""

import json
import os
import re
import socket
import sys
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG_FEED_SOCKET = os.environ.get(
    "LOG_FEED_SOCKET", "/run/pv/services/log-feed.sock"
)
LOG_FEED_PATH = "/subscribe"

DEEPSEEK_UDS = os.environ.get("DEEPSEEK_UDS", "/run/pv/services/deepseek-r1.sock")
DEEPSEEK_URL = os.environ.get("DEEPSEEK_URL", "http://127.0.0.1:8080")
DEEPSEEK_TIMEOUT = float(os.environ.get("DEEPSEEK_TIMEOUT", "60"))

SYSTEM_PROMPT = (
    "You are a log triage assistant running on an embedded device. "
    "Given a single error log line with surrounding context, decide "
    "whether it warrants a human-facing warning. "
    "Respond with ONLY a compact JSON object on one line, no prose, "
    "matching this schema: "
    '{"severity":"critical|warn|info|ignore","warn":<bool>,"reason":"<short>"}. '
    "severity=critical means immediate attention; warn means notify; "
    "info or ignore mean suppress. Be conservative — most noisy or "
    "transient errors should be 'ignore'."
)

_subscribers_lock = threading.Lock()
_subscribers = []


def log(msg: str) -> None:
    sys.stderr.write(f"log-anomaly: {msg}\n")


def _broadcast(event: dict) -> None:
    line = (json.dumps(event) + "\n").encode()
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
# DeepSeek client (HTTP over TCP or UDS)
# ---------------------------------------------------------------------------

def _build_prompt(event: dict) -> list[dict]:
    context_before = "\n".join(event.get("pre_context") or [])
    context_after = "\n".join(event.get("post_context") or [])
    user = (
        f"Source: {event.get('source')}\n"
        f"--- before ---\n{context_before}\n"
        f"--- match ---\n{event.get('match')}\n"
        f"--- after ---\n{context_after}\n"
    )
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user},
    ]


def _post_chat_tcp(payload: dict) -> dict:
    req = urllib.request.Request(
        f"{DEEPSEEK_URL}/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=DEEPSEEK_TIMEOUT) as resp:
        return json.loads(resp.read().decode())


def _post_chat_uds(payload: dict) -> dict:
    body = json.dumps(payload).encode()
    req = (
        b"POST /v1/chat/completions HTTP/1.1\r\n"
        b"Host: deepseek-r1\r\n"
        b"Content-Type: application/json\r\n"
        b"Content-Length: " + str(len(body)).encode() + b"\r\n"
        b"Connection: close\r\n\r\n"
    ) + body

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(DEEPSEEK_TIMEOUT)
        s.connect(DEEPSEEK_UDS)
        s.sendall(req)
        buf = b""
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk

    header, _, body_bytes = buf.partition(b"\r\n\r\n")
    # llama-server replies with Content-Length, not chunked, for non-stream.
    return json.loads(body_bytes.decode("utf-8", errors="replace"))


def query_llm(event: dict) -> dict:
    payload = {
        "model": "deepseek-r1",
        "messages": _build_prompt(event),
        "temperature": 0.0,
        "max_tokens": 200,
        "stream": False,
    }
    if os.path.exists(DEEPSEEK_UDS):
        raw = _post_chat_uds(payload)
    else:
        raw = _post_chat_tcp(payload)

    content = raw["choices"][0]["message"]["content"].strip()
    # R1 models like to wrap reasoning in <think>...</think>; strip it.
    content = re.sub(r"<think>.*?</think>", "", content, flags=re.DOTALL).strip()
    # Grab the first JSON object in the response.
    match = re.search(r"\{.*\}", content, re.DOTALL)
    verdict = {"severity": "unknown", "warn": False, "reason": content[:200]}
    if match:
        try:
            parsed = json.loads(match.group(0))
            verdict.update({
                "severity": parsed.get("severity", "unknown"),
                "warn": bool(parsed.get("warn", False)),
                "reason": parsed.get("reason", "")[:200],
            })
        except json.JSONDecodeError:
            pass
    return verdict


# ---------------------------------------------------------------------------
# log-feed consumer (reuses the chunked NDJSON reader pattern)
# ---------------------------------------------------------------------------

def _read_chunked_lines(sock):
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
            sock.connect(LOG_FEED_SOCKET)
            sock.sendall(
                f"GET {LOG_FEED_PATH} HTTP/1.1\r\n"
                f"Host: log-feed\r\n"
                f"Accept: application/x-ndjson\r\n"
                f"Connection: keep-alive\r\n\r\n".encode()
            )
            log(f"subscribed to {LOG_FEED_SOCKET}{LOG_FEED_PATH}")
            backoff = 1.0
            for line in _read_chunked_lines(sock):
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                try:
                    verdict = query_llm(event)
                except Exception as e:
                    log(f"LLM query failed: {e!r}")
                    verdict = {
                        "severity": "unknown",
                        "warn": True,
                        "reason": f"llm_error: {e!r}",
                    }
                _broadcast({
                    "event_id": event.get("event_id"),
                    "ts": time.time(),
                    "ts_event": event.get("ts"),
                    "source": event.get("source"),
                    "match": event.get("match"),
                    "verdict": verdict,
                })
        except Exception as e:
            log(f"feed connection lost: {e!r}")
            time.sleep(backoff)
            backoff = min(backoff * 2, 15.0)
        finally:
            try:
                sock.close()
            except Exception:
                pass


# ---------------------------------------------------------------------------
# Publish side
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    def address_string(self):
        return "uds"

    def log_message(self, fmt, *args):
        sys.stderr.write("log-anomaly: " + (fmt % args) + "\n")

    def do_GET(self):
        if self.path == "/info":
            body = json.dumps({
                "service": "log-anomaly",
                "upstream_feed": LOG_FEED_SOCKET,
                "deepseek_uds": DEEPSEEK_UDS,
                "deepseek_url": DEEPSEEK_URL,
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
            self.log_message("subscriber joined (total=%d)", len(_subscribers))
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
    log(f"publishing on {socket_path}")
    httpd.serve_forever()


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "/run/logs/anomaly.sock"
    run(path)
