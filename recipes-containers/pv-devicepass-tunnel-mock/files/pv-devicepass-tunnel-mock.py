#!/usr/bin/env python3
"""
Mock tunnel server for testing pv-devicepass WebSocket tunnel client.

Listens on a Unix socket, accepts WebSocket connections from pv-devicepass,
and periodically sends JSON commands to exercise the operation dispatch.

Protocol (JSON over WebSocket text frames):
  Server -> Client: {"id":"req-N","method":"GET","path":"/containers","body":null}
  Client -> Server: {"id":"req-N","status":200,"body":[...]}
"""

import asyncio
import hashlib
import base64
import json
import os
import struct
import sys
import time

SOCKET_PATH = os.environ.get("TUNNEL_SOCKET", "/run/tunnel-mock/tunnel.sock")
POLL_INTERVAL = int(os.environ.get("TUNNEL_POLL_INTERVAL", "10"))

# Endpoints to poll periodically
POLL_COMMANDS = [
    {"method": "GET", "path": "/containers"},
    {"method": "GET", "path": "/skills"},
    {"method": "GET", "path": "/status"},
    {"method": "GET", "path": "/daemons"},
]

WS_MAGIC = b"258EAFA5-E914-47DA-95CA-5AB9FFE11246"


def ws_accept_key(client_key):
    """Compute Sec-WebSocket-Accept from client key."""
    digest = hashlib.sha1(client_key.encode() + WS_MAGIC).digest()
    return base64.b64encode(digest).decode()


def ws_encode_frame(payload):
    """Encode a WebSocket text frame (server-side, no masking)."""
    data = payload.encode() if isinstance(payload, str) else payload
    frame = bytearray()
    frame.append(0x81)  # FIN + text opcode

    length = len(data)
    if length < 126:
        frame.append(length)
    elif length <= 0xFFFF:
        frame.append(126)
        frame.extend(struct.pack("!H", length))
    else:
        frame.append(127)
        frame.extend(struct.pack("!Q", length))

    frame.extend(data)
    return bytes(frame)


def ws_decode_frame(data):
    """
    Decode a WebSocket frame. Returns (opcode, payload, consumed) or None if incomplete.
    """
    if len(data) < 2:
        return None

    opcode = data[0] & 0x0F
    masked = (data[1] >> 7) & 1
    length = data[1] & 0x7F
    pos = 2

    if length == 126:
        if len(data) < 4:
            return None
        length = struct.unpack("!H", data[2:4])[0]
        pos = 4
    elif length == 127:
        if len(data) < 10:
            return None
        length = struct.unpack("!Q", data[2:10])[0]
        pos = 10

    if masked:
        if len(data) < pos + 4:
            return None
        mask = data[pos:pos + 4]
        pos += 4
    else:
        mask = None

    if len(data) < pos + length:
        return None

    payload = data[pos:pos + length]
    if mask:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))

    return (opcode, payload, pos + length)


async def handle_client(reader, writer):
    """Handle a single WebSocket connection from pv-devicepass."""
    peer = "pv-devicepass"
    print(f"tunnel-mock: new connection from {peer}", flush=True)

    # Read HTTP upgrade request
    request = b""
    while b"\r\n\r\n" not in request:
        chunk = await reader.read(4096)
        if not chunk:
            writer.close()
            return
        request += chunk

    # Extract Sec-WebSocket-Key
    ws_key = None
    for line in request.decode(errors="replace").split("\r\n"):
        if line.lower().startswith("sec-websocket-key:"):
            ws_key = line.split(":", 1)[1].strip()
            break

    if not ws_key:
        print("tunnel-mock: no WebSocket key in upgrade request", flush=True)
        writer.close()
        return

    # Send 101 Switching Protocols
    accept_key = ws_accept_key(ws_key)
    response = (
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Accept: {accept_key}\r\n"
        "\r\n"
    )
    writer.write(response.encode())
    await writer.drain()
    print("tunnel-mock: WebSocket handshake complete", flush=True)

    # Start polling task
    req_counter = [0]
    poll_idx = [0]

    async def poll_loop():
        while True:
            await asyncio.sleep(POLL_INTERVAL)
            cmd = POLL_COMMANDS[poll_idx[0] % len(POLL_COMMANDS)]
            poll_idx[0] += 1
            req_counter[0] += 1
            req_id = f"poll-{req_counter[0]}"

            msg = json.dumps({
                "id": req_id,
                "method": cmd["method"],
                "path": cmd["path"],
                "body": None,
            })
            frame = ws_encode_frame(msg)
            try:
                writer.write(frame)
                await writer.drain()
                print(f"tunnel-mock: sent {cmd['method']} {cmd['path']} (id={req_id})",
                      flush=True)
            except Exception as e:
                print(f"tunnel-mock: send error: {e}", flush=True)
                break

    poll_task = asyncio.ensure_future(poll_loop())

    # Read response frames
    buf = b""
    try:
        while True:
            chunk = await reader.read(65536)
            if not chunk:
                break
            buf += chunk

            while True:
                result = ws_decode_frame(buf)
                if result is None:
                    break

                opcode, payload, consumed = result
                buf = buf[consumed:]

                if opcode == 0x08:  # close
                    print("tunnel-mock: received close frame", flush=True)
                    poll_task.cancel()
                    writer.close()
                    return

                if opcode == 0x09:  # ping
                    pong = bytearray([0x8A, 0x00])
                    writer.write(bytes(pong))
                    await writer.drain()
                    continue

                if opcode == 0x0A:  # pong
                    continue

                # Text frame — parse response
                try:
                    resp = json.loads(payload.decode())
                    req_id = resp.get("id", "?")
                    status = resp.get("status", "?")
                    body = resp.get("body")
                    body_preview = json.dumps(body)[:200] if body else "null"
                    print(f"tunnel-mock: response id={req_id} status={status} "
                          f"body={body_preview}", flush=True)
                except json.JSONDecodeError:
                    print(f"tunnel-mock: invalid JSON response: {payload[:100]}",
                          flush=True)
    except asyncio.CancelledError:
        pass
    except Exception as e:
        print(f"tunnel-mock: read error: {e}", flush=True)
    finally:
        poll_task.cancel()
        writer.close()
        print("tunnel-mock: connection closed", flush=True)


async def main():
    # Ensure socket directory exists
    sock_dir = os.path.dirname(SOCKET_PATH)
    os.makedirs(sock_dir, exist_ok=True)

    # Remove stale socket
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass

    server = await asyncio.start_unix_server(handle_client, path=SOCKET_PATH)
    os.chmod(SOCKET_PATH, 0o666)
    print(f"tunnel-mock: listening on {SOCKET_PATH}", flush=True)
    print(f"tunnel-mock: polling interval {POLL_INTERVAL}s", flush=True)

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("tunnel-mock: shutting down", flush=True)
