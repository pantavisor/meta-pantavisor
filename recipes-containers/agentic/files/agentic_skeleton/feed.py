"""
NDJSON xconnect feed subscriber + publisher.

Pantavisor xconnect REST services that expose a streaming /subscribe endpoint
return chunked transfer encoding with one JSON object per chunk (or per
newline within a chunk). agentic-log-feed and agentic-camera-* follow this
pattern. The skeleton provides a small client so product agent-apps don't
each reimplement the chunked-NDJSON dance.
"""

import http.client
import json
import os
import socket
import threading


class _UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, path, timeout=None):
        super().__init__("localhost", timeout=timeout)
        self._uds_path = path

    def connect(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        if self.timeout is not None:
            s.settimeout(self.timeout)
        s.connect(self._uds_path)
        self.sock = s


class NDJSONSubscriber:
    """Iterate over events from an xconnect REST feed.

    The feed is expected to GET-stream NDJSON (chunked or plain). We tolerate
    both transfer-encoding=chunked and identity, accumulate bytes until we
    have a full line, parse it as JSON, and yield. If the connection drops
    we re-connect — feeds restart cleanly across container restarts.
    """

    def __init__(self, socket_path, path="/subscribe"):
        self._sock = socket_path
        self._path = path

    def __iter__(self):
        while True:
            try:
                yield from self._stream_once()
            except (OSError, http.client.HTTPException) as e:
                # Backoff is the caller's responsibility; we just reopen on
                # the next iteration. Feeds typically restart in <1s.
                _ = e
                continue

    def _stream_once(self):
        conn = _UnixHTTPConnection(self._sock, timeout=None)
        try:
            conn.request("GET", self._path)
            resp = conn.getresponse()
            if resp.status != 200:
                raise RuntimeError(
                    f"feed {self._sock}{self._path} returned HTTP {resp.status}"
                )
            buf = b""
            while True:
                chunk = resp.read(4096)
                if not chunk:
                    return
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        yield json.loads(line)
                    except json.JSONDecodeError:
                        # Skip garbage lines rather than crashing the loop.
                        continue
        finally:
            conn.close()


class NDJSONPublisher:
    """Tiny xconnect-side server that fans out events to subscribers.

    Used as the agent-app's *action sink*: every final answer or tool
    decision is published as a JSON line to anyone connected to /subscribe.
    Downstream containers (UI, MQTT bridge, logger) consume it.

    Implementation cribbed from agentic-log-anomaly: a minimal threaded
    AF_UNIX HTTP server with one in-memory subscriber list. We don't bother
    with persistence or fanout buffers — if a subscriber is slow, it drops
    events. Agent-app outputs are infrequent enough that this is fine.
    """

    def __init__(self, socket_path):
        self._sock_path = socket_path
        self._lock = threading.Lock()
        self._subs = []
        self._server = None
        self._thread = None

    def start(self):
        from http.server import BaseHTTPRequestHandler, HTTPServer

        publisher = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, fmt, *args):
                return  # silence default access log; runtime emits its own

            def do_GET(self):
                if self.path != "/subscribe":
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header("Content-Type", "application/x-ndjson")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "keep-alive")
                self.end_headers()
                publisher._add(self.wfile)
                try:
                    while True:
                        data = self.rfile.read(1)
                        if not data:
                            break
                except Exception:
                    pass
                finally:
                    publisher._remove(self.wfile)

        class UnixHTTPServer(HTTPServer):
            address_family = socket.AF_UNIX

            def server_bind(self):
                if os.path.exists(self.server_address):
                    os.unlink(self.server_address)
                socket.socket.bind(self.socket, self.server_address)
                os.chmod(self.server_address, 0o666)
                self.server_name = "localhost"
                self.server_port = 0

        self._server = UnixHTTPServer(self._sock_path, Handler)
        self._thread = threading.Thread(
            target=self._server.serve_forever, daemon=True
        )
        self._thread.start()

    def publish(self, event: dict):
        line = (json.dumps(event) + "\n").encode("utf-8")
        with self._lock:
            dead = []
            for w in self._subs:
                try:
                    w.write(line)
                    w.flush()
                except Exception:
                    dead.append(w)
            for w in dead:
                self._subs.remove(w)

    def _add(self, w):
        with self._lock:
            self._subs.append(w)

    def _remove(self, w):
        with self._lock:
            try:
                self._subs.remove(w)
            except ValueError:
                pass
