#!/usr/bin/python3
"""
OpenAI-compatible gateway for the Jetson Nano build of pv-unsloth.

Unsloth needs PyTorch 2.x on CUDA 11.8+, which the Nano (sm_53, CUDA 10.2)
cannot run, so this serves the same API as the repository's server.py with
the standard library only, and reports the GPU through the CUDA driver API.
"""

import ctypes
import json
import os
import signal
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8000"))
MODELS_DIR = "/models"
CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR = 75
CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR = 76


def log(msg):
    print(f"[Unsloth Gateway] {msg}", flush=True)


def probe_gpu():
    """Open the GPU with the CUDA driver API; never raises."""
    try:
        cuda = ctypes.CDLL("libcuda.so.1")
    except OSError as e:
        return {"cuda_available": False, "error": f"libcuda: {e}"}

    def check(name, rc):
        if rc != 0:
            raise RuntimeError(f"{name} failed with CUDA error {rc}")

    try:
        check("cuInit", cuda.cuInit(0))
        count = ctypes.c_int()
        check("cuDeviceGetCount", cuda.cuDeviceGetCount(ctypes.byref(count)))
        if count.value < 1:
            return {"cuda_available": False, "error": "no CUDA devices"}

        dev = ctypes.c_int()
        check("cuDeviceGet", cuda.cuDeviceGet(ctypes.byref(dev), 0))
        name = ctypes.create_string_buffer(256)
        check("cuDeviceGetName", cuda.cuDeviceGetName(name, len(name), dev))
        mem = ctypes.c_size_t()
        check("cuDeviceTotalMem",
              cuda.cuDeviceTotalMem_v2(ctypes.byref(mem), dev))
        major, minor = ctypes.c_int(), ctypes.c_int()
        check("cuDeviceGetAttribute", cuda.cuDeviceGetAttribute(
            ctypes.byref(major), CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, dev))
        check("cuDeviceGetAttribute", cuda.cuDeviceGetAttribute(
            ctypes.byref(minor), CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, dev))

        # A context proves the device is usable, not only enumerable.
        ctx = ctypes.c_void_p()
        check("cuCtxCreate", cuda.cuCtxCreate_v2(ctypes.byref(ctx), 0, dev))
        check("cuCtxDestroy", cuda.cuCtxDestroy_v2(ctx))

        return {
            "cuda_available": True,
            "device": name.value.decode(errors="replace"),
            "compute_capability": f"{major.value}.{minor.value}",
            "memory_total_gb": round(mem.value / (1024 ** 3), 2),
        }
    except RuntimeError as e:
        return {"cuda_available": False, "error": str(e)}


GPU = {}

CHAT_PAGE = b"""<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pantavisor AI Box</title>
<style>
body{font-family:system-ui,sans-serif;margin:0;display:flex;flex-direction:column;height:100vh;background:#111;color:#eee}
header{padding:.6em 1em;background:#222;font-size:.9em}
#log{flex:1;overflow-y:auto;padding:1em}
.m{margin:.4em 0;padding:.5em .8em;border-radius:8px;max-width:80%;white-space:pre-wrap}
.user{background:#2b5;color:#000;margin-left:auto}
.assistant{background:#333}
.error{background:#a33}
form{display:flex;padding:.6em;background:#222}
input{flex:1;padding:.6em;font-size:1em;border:0;border-radius:6px}
button{margin-left:.5em;padding:.6em 1.2em;font-size:1em;border:0;border-radius:6px}
</style></head><body>
<header id="gpu">Pantavisor AI Box</header>
<div id="log"></div>
<form id="f"><input id="q" autocomplete="off" placeholder="Message" autofocus><button>Send</button></form>
<script>
const log = document.getElementById("log"), q = document.getElementById("q");
const messages = [];
function add(role, text) {
  const d = document.createElement("div");
  d.className = "m " + role; d.textContent = text;
  log.appendChild(d); log.scrollTop = log.scrollHeight;
}
fetch("/health").then(r => r.json()).then(h => {
  document.getElementById("gpu").textContent = h.cuda_available
    ? `Pantavisor AI Box - ${h.device} (sm ${h.compute_capability}, ${h.memory_total_gb} GB)`
    : `Pantavisor AI Box - no GPU: ${h.error}`;
});
document.getElementById("f").onsubmit = async e => {
  e.preventDefault();
  const text = q.value.trim();
  if (!text) return;
  q.value = "";
  messages.push({role: "user", content: text});
  add("user", text);
  try {
    const r = await fetch("/v1/chat/completions", {method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({messages})});
    const j = await r.json();
    if (!r.ok) throw new Error(j.error || r.status);
    const msg = j.choices[0].message;
    messages.push(msg);
    add("assistant", msg.content);
  } catch (err) {
    add("error", "Error: " + err.message);
  }
};
</script></body></html>
"""


def list_models():
    models = ["unsloth-default"]
    if os.path.isdir(MODELS_DIR):
        models.extend(sorted(os.listdir(MODELS_DIR)))
    return {
        "object": "list",
        "data": [{"id": m, "object": "model", "owned_by": "pantavisor-box"}
                 for m in models],
    }


def chat_completion(req):
    messages = req.get("messages") or []
    model = req.get("model") or "unsloth-local"
    prompt = "\n".join(f"{m.get('role')}: {m.get('content')}"
                       for m in messages) + "\nassistant: "
    if GPU.get("cuda_available"):
        text = (f"Hello from the Sovereign Pantavisor AI Box! Processed "
                f"{len(messages)} messages locally on {GPU['device']}.")
    else:
        text = "CUDA acceleration is not available on this device."
    now = int(time.time())
    return {
        "id": f"chatcmpl-{now}",
        "object": "chat.completion",
        "created": now,
        "model": model,
        "choices": [{
            "index": 0,
            "message": {"role": "assistant", "content": text},
            "finish_reason": "stop",
        }],
        "usage": {
            "prompt_tokens": len(prompt.split()),
            "completion_tokens": len(text.split()),
            "total_tokens": len(prompt.split()) + len(text.split()),
        },
    }


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, content_type="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self._send(200, CHAT_PAGE, "text/html; charset=utf-8")
        elif self.path == "/health":
            self._send(200, {"status": "healthy", **GPU})
        elif self.path == "/v1/models":
            self._send(200, list_models())
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            self._send(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            req = json.loads(self.rfile.read(length) or b"{}")
            if not isinstance(req.get("messages"), list):
                raise ValueError("'messages' must be a list")
        except (ValueError, json.JSONDecodeError) as e:
            self._send(400, {"error": str(e)})
            return
        self._send(200, chat_completion(req))

    def log_message(self, fmt, *args):
        log(f"{self.address_string()} {fmt % args}")


def signal_ready():
    try:
        subprocess.run(["pvcontrol", "signal", "ready"], check=False)
    except OSError as e:
        log(f"cannot signal READY to Pantavisor: {e}")


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    GPU.update(probe_gpu())
    if GPU["cuda_available"]:
        log(f"GPU ready: {GPU['device']} (sm {GPU['compute_capability']}, "
            f"{GPU['memory_total_gb']} GB)")
    else:
        log(f"WARNING: no usable CUDA GPU: {GPU['error']}")

    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    log(f"listening on port {PORT}")
    signal_ready()
    server.serve_forever()


if __name__ == "__main__":
    main()
