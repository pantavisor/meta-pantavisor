"""
pv-llama-chat — minimal HTTP server bridging a browser to pv-llama.

Three jobs:

  1. Serve a static single-page UI (index.html) on `/`.
  2. Proxy `/api/models` and `/api/chat` to pv-llama's OpenAI-compatible
     HTTP endpoint over its UDS, including SSE streaming for chat.
  3. Tap every completion that flows through us and rebroadcast a
     compact summary on `/api/monitor` as Server-Sent Events, so the
     UI's "Monitor" tab can show what agent-apps in the same image
     are sending to the model in real time.

Stdlib-only on purpose: matches the agentic skeleton's deps and keeps
the container small. No frameworks, no async — one thread per
connection via ThreadingHTTPServer.
"""

import argparse
import json
import logging
import os
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from queue import Queue, Full, Empty

log = logging.getLogger("pv-llama-chat")


# ----------------------------------------------------------------------
# UDS HTTP client. http.client doesn't speak unix sockets natively, so
# we open the socket ourselves, write a raw HTTP/1.1 request, and yield
# response chunks back to the caller. Caller may read everything (JSON)
# or stream (SSE) — same primitive.
# ----------------------------------------------------------------------

def _uds_request(uds_path, method, path, body=None, headers=None,
                 timeout=300):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(uds_path)

    h = {
        "Host": "pv-llama",
        "Connection": "close",
        "Accept": "*/*",
    }
    if headers:
        h.update(headers)
    if body is not None:
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode("utf-8")
            h.setdefault("Content-Type", "application/json")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        h["Content-Length"] = str(len(body))

    # HTTP/1.0 here on purpose: pantavisor's xconnect REST plugin
    # doesn't pass HTTP/1.1 keep-alive cleanly, so the response stalls
    # waiting for a close. 1.0 gets a clean "read until EOF" semantic
    # that the proxy + downstream llama-swap both honor.
    req = "%s %s HTTP/1.0\r\n" % (method, path)
    for k, v in h.items():
        req += "%s: %s\r\n" % (k, v)
    req += "\r\n"
    s.sendall(req.encode("ascii"))
    if body:
        s.sendall(body)
    return s


def _read_body(sock, hdrs, leftover):
    """Read the response body honoring Content-Length when present;
    fall back to read-until-EOF otherwise. We can't blindly read until
    EOF — pantavisor's xconnect REST proxy keeps the upstream socket
    open after a Content-Length response (despite our HTTP/1.0 +
    Connection: close request), so a naive read-till-close hangs until
    timeout.
    """
    body = bytes(leftover)
    cl = hdrs.get("content-length")
    if cl is not None:
        try:
            need = int(cl)
        except ValueError:
            need = -1
        if need >= 0:
            while len(body) < need:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                body += chunk
            return body
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        body += chunk
    return body


def _read_status_and_headers(sock):
    """Read up to end-of-headers, return (status, reason, headers, leftover_bytes)."""
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            break
        buf += chunk
    head, _, leftover = buf.partition(b"\r\n\r\n")
    lines = head.split(b"\r\n")
    status_line = lines[0].decode("iso-8859-1")
    parts = status_line.split(" ", 2)
    status = int(parts[1]) if len(parts) >= 2 else 0
    reason = parts[2] if len(parts) >= 3 else ""
    hdrs = {}
    for ln in lines[1:]:
        if b":" in ln:
            k, v = ln.split(b":", 1)
            hdrs[k.decode("ascii").strip().lower()] = v.decode("iso-8859-1").strip()
    return status, reason, hdrs, leftover


# ----------------------------------------------------------------------
# Monitor pub/sub. Every completed chat call drops a compact record
# onto the bus; SSE subscribers each get their own bounded queue.
# Bounded so a slow browser can't make us OOM.
# ----------------------------------------------------------------------

class MonitorBus:
    def __init__(self, history=50, queue_size=100):
        self._lock = threading.Lock()
        self._subscribers = []
        self._history = []
        self._history_max = history
        self._queue_size = queue_size

    def subscribe(self):
        q = Queue(maxsize=self._queue_size)
        with self._lock:
            self._subscribers.append(q)
            # Replay recent history so a freshly-opened monitor tab
            # sees what just happened, not a blank page.
            for rec in self._history:
                try:
                    q.put_nowait(rec)
                except Full:
                    break
        return q

    def unsubscribe(self, q):
        with self._lock:
            try:
                self._subscribers.remove(q)
            except ValueError:
                pass

    def publish(self, rec):
        with self._lock:
            self._history.append(rec)
            if len(self._history) > self._history_max:
                self._history.pop(0)
            dead = []
            for q in self._subscribers:
                try:
                    q.put_nowait(rec)
                except Full:
                    # Subscriber is too slow; drop them rather than block.
                    dead.append(q)
            for q in dead:
                self._subscribers.remove(q)


BUS = MonitorBus()


# ----------------------------------------------------------------------
# Request handler.
# ----------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = "pv-llama-chat/1.0"

    def log_message(self, fmt, *args):
        log.info("%s - " + fmt, self.address_string(), *args)

    # ----- static -----

    def _serve_static(self, path):
        safe = "index.html" if path in ("/", "") else path.lstrip("/")
        if "/" in safe or ".." in safe:
            self.send_error(404)
            return
        full = os.path.join(self.server.www_root, safe)
        if not os.path.isfile(full):
            self.send_error(404)
            return
        ctype = "text/html; charset=utf-8" if safe.endswith(".html") else \
                "application/javascript" if safe.endswith(".js") else \
                "text/css" if safe.endswith(".css") else \
                "application/octet-stream"
        with open(full, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    # ----- /api/models -----

    def _api_models(self):
        try:
            sock = _uds_request(self.server.uds, "GET", "/v1/models",
                                timeout=10)
            status, _, hdrs, leftover = _read_status_and_headers(sock)
            body = _read_body(sock, hdrs, leftover)
            sock.close()
        except Exception as e:
            self.send_error(502, "pv-llama unreachable: %s" % e)
            return
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # ----- /api/chat (POST, optional SSE) -----

    def _api_chat(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw)
        except Exception:
            self.send_error(400, "invalid JSON")
            return
        stream = bool(payload.get("stream"))

        rec_id = "%d" % int(time.time() * 1000)
        rec_started = time.time()
        rec_model = payload.get("model", "")
        # Capture a short summary of the input so the monitor view has
        # something legible without leaking entire system prompts.
        rec_input = _summarize_messages(payload.get("messages", []))

        try:
            sock = _uds_request(self.server.uds, "POST",
                                "/v1/chat/completions", body=payload,
                                timeout=600)
            status, reason, hdrs, leftover = _read_status_and_headers(sock)
        except Exception as e:
            BUS.publish({
                "id": rec_id, "model": rec_model, "input": rec_input,
                "error": str(e),
                "started_at": rec_started, "duration_s": 0.0,
            })
            self.send_error(502, "pv-llama unreachable: %s" % e)
            return

        # Pass status + content-type through to the browser.
        ctype = hdrs.get("content-type",
                         "text/event-stream" if stream else "application/json")
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        # Stream + capture for the monitor. For non-streaming responses
        # llama-swap sends Content-Length and the upstream proxy keeps
        # the socket open afterward — so we must stop reading at the
        # advertised length rather than waiting for EOF.
        captured = bytearray(leftover)
        cl = None
        if not stream:
            try:
                cl = int(hdrs.get("content-length", "")) if "content-length" in hdrs else None
            except ValueError:
                cl = None
        try:
            self.wfile.write(leftover)
            self.wfile.flush()
        except Exception:
            sock.close()
            return

        try:
            while True:
                if cl is not None and len(captured) >= cl:
                    break
                chunk = sock.recv(4096)
                if not chunk:
                    break
                captured.extend(chunk)
                try:
                    self.wfile.write(chunk)
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    # Browser went away — keep draining pv-llama so it
                    # doesn't stall, but stop trying to forward.
                    if cl is not None:
                        remain = cl - len(captured)
                        while remain > 0:
                            c = sock.recv(min(4096, remain))
                            if not c:
                                break
                            remain -= len(c)
                    else:
                        while sock.recv(4096):
                            pass
                    break
        finally:
            sock.close()

        # Decode the captured response into a one-line monitor record.
        text = _extract_assistant_text(captured.decode("utf-8", "replace"),
                                       stream=stream)
        BUS.publish({
            "id": rec_id,
            "model": rec_model,
            "input": rec_input,
            "output": text[:500],
            "stream": stream,
            "started_at": rec_started,
            "duration_s": round(time.time() - rec_started, 2),
        })

    # ----- /api/monitor (SSE) -----

    def _api_monitor(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        q = BUS.subscribe()
        try:
            # Initial nudge so the browser's onopen fires promptly.
            self.wfile.write(b": hello\n\n")
            self.wfile.flush()
            while True:
                try:
                    rec = q.get(timeout=15)
                except Empty:
                    # Heartbeat — keeps middleware proxies (and the
                    # browser) from giving up on the SSE stream.
                    try:
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
                    except Exception:
                        return
                    continue
                line = "data: " + json.dumps(rec) + "\n\n"
                try:
                    self.wfile.write(line.encode("utf-8"))
                    self.wfile.flush()
                except Exception:
                    return
        finally:
            BUS.unsubscribe(q)

    # ----- routing -----

    def do_GET(self):
        if self.path == "/api/models":
            return self._api_models()
        if self.path == "/api/monitor":
            return self._api_monitor()
        if self.path.startswith("/api/"):
            return self.send_error(404)
        return self._serve_static(self.path)

    def do_POST(self):
        if self.path == "/api/chat":
            return self._api_chat()
        return self.send_error(404)


def _summarize_messages(messages):
    """One-line input summary: last user/system snippet, role-prefixed."""
    if not isinstance(messages, list) or not messages:
        return ""
    last = messages[-1]
    role = last.get("role", "?") if isinstance(last, dict) else "?"
    content = last.get("content", "") if isinstance(last, dict) else ""
    if not isinstance(content, str):
        content = json.dumps(content)
    s = content.replace("\n", " ").strip()
    if len(s) > 160:
        s = s[:160] + "…"
    return "[%s] %s" % (role, s)


def _extract_assistant_text(blob, stream):
    """Pull the assistant text out of either a JSON response or an SSE
    stream of OpenAI chat-completion deltas.
    """
    if not blob:
        return ""
    if not stream:
        try:
            obj = json.loads(blob)
            return obj["choices"][0]["message"]["content"] or ""
        except Exception:
            return blob[:500]
    # SSE: "data: {...}\n\n", terminated by "data: [DONE]\n\n".
    out = []
    for line in blob.split("\n"):
        line = line.strip()
        if not line.startswith("data:"):
            continue
        data = line[5:].strip()
        if data == "[DONE]":
            break
        try:
            obj = json.loads(data)
            delta = obj["choices"][0].get("delta", {})
            piece = delta.get("content")
            if piece:
                out.append(piece)
        except Exception:
            continue
    return "".join(out)


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, addr, www_root, uds):
        super().__init__(addr, Handler)
        self.www_root = www_root
        self.uds = uds


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=8080)
    p.add_argument("--bind", default="0.0.0.0")
    p.add_argument("--uds", default="/run/pv/services/pv-llama.sock")
    p.add_argument("--www", default=os.path.dirname(os.path.abspath(__file__)))
    args = p.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
        stream=sys.stderr,
    )
    log.info("pv-llama-chat listening on %s:%d, upstream=%s, www=%s",
             args.bind, args.port, args.uds, args.www)
    Server((args.bind, args.port), args.www, args.uds).serve_forever()


if __name__ == "__main__":
    main()
