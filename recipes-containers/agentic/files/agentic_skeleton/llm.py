"""
pv-llama client — OpenAI-compatible chat completions over HTTP-on-UDS or TCP.

Why this lives in the skeleton:

The xconnect-mediated path to pv-llama is HTTP-over-Unix-domain-socket — the
provider's services.json declares type=rest, the consumer mounts the socket,
and HTTP framing rides over an `AF_UNIX` stream. Python's stdlib `http.client`
does not speak unix sockets, and we don't want every product to roll its own.
Same client transparently handles TCP for development.
"""

import http.client
import json
import os
import socket


class _UnixHTTPConnection(http.client.HTTPConnection):
    """http.client.HTTPConnection with the underlying socket switched to AF_UNIX.

    `host` is the path to the unix socket; `port` is unused but the parent
    class wants one. We override `connect()` so the request/response framing
    is identical to plain HTTP/1.1 over TCP — the consumer code at the call
    site does not need to know which transport it's using.
    """

    def __init__(self, path, timeout=60):
        super().__init__("localhost", timeout=timeout)
        self._uds_path = path

    def connect(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(self.timeout)
        s.connect(self._uds_path)
        self.sock = s


class LlamaClient:
    """OpenAI-compatible chat client for pv-llama.

    Construct with either uds=<path> (preferred — what xconnect provides) or
    url=<http://host:port> for development. The first one that resolves wins.
    """

    def __init__(self, uds=None, url=None, timeout=120):
        self._uds = uds if (uds and os.path.exists(uds)) else None
        self._url = url if not self._uds else None
        self._timeout = timeout
        if not (self._uds or self._url):
            raise RuntimeError(
                f"LlamaClient: neither uds={uds!r} exists nor url={url!r} set"
            )

    def _conn(self):
        if self._uds:
            return _UnixHTTPConnection(self._uds, timeout=self._timeout)
        # url like "http://host:port"
        host = self._url.split("://", 1)[1]
        return http.client.HTTPConnection(host, timeout=self._timeout)

    def chat(self, messages, *, model, tools=None, grammar=None,
             max_tokens=512, temperature=0.0, stop=None):
        """Run one chat-completion turn.

        Returns the parsed top-level response dict from llama-server. The
        caller picks message.content / tool_calls out of the response — we
        don't pre-process because different llama.cpp versions and different
        models expose tool calls slightly differently and we want the agent
        loop to see the raw shape.
        """
        body = {
            "model": model,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
        }
        if tools:
            body["tools"] = tools
        if grammar:
            # llama.cpp non-standard extension; ignored by other backends.
            body["grammar"] = grammar
        if stop:
            body["stop"] = stop

        conn = self._conn()
        try:
            conn.request(
                "POST", "/v1/chat/completions",
                body=json.dumps(body),
                headers={"Content-Type": "application/json"},
            )
            resp = conn.getresponse()
            data = resp.read()
            if resp.status >= 400:
                raise RuntimeError(
                    f"pv-llama returned HTTP {resp.status}: {data[:200]!r}"
                )
            return json.loads(data)
        finally:
            conn.close()
