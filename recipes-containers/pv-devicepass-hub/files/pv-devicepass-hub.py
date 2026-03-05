#!/usr/bin/env python3
"""
DevicePass Hub — fleet management rendezvous service with on-chain auth.

Single TCP server with path-based routing:

  GET /tunnel (WebSocket upgrade)
    - Accepts WebSocket connections from pv-devicepass C daemon
    - Challenge-response auth: device proves Ethereum identity
    - Hub verifies on-chain passport (DevicePassRegistry)
    - Polls devices for containers/skills/status/daemons
    - Routes guardian API requests to devices via tunnel

  GET  /v1/devices            — list devices (guardian-scoped)
  GET  /v1/devices/{addr}     — single device detail
  POST /v1/devices/{addr}/call — route request to device via tunnel
  POST /v1/devices/group/call — fan-out to multiple devices
  GET  /v1/health             — hub health check (unauthenticated)

Authentication:
  Device → Hub: EIP-191 challenge-response over WebSocket
  Guardian → Hub: Signed REST headers (X-DevicePass-*)
  Hub → Contract: eth_call to passports(address) via JSON-RPC

Tunnel protocol (JSON over WebSocket text frames):
  Hub -> Device: {"id":"req-N","method":"GET","path":"/containers","body":null}
  Device -> Hub: {"id":"req-N","status":200,"body":[...]}
"""

import asyncio
import hashlib
import base64
import json
import os
import struct
import time
import traceback
import http.client
from urllib.parse import urlparse

# --- Configuration ---

HUB_HOST = os.environ.get("HUB_HOST", "0.0.0.0")
HUB_PORT = int(os.environ.get("HUB_PORT", "8080"))
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "15"))
REQUEST_TIMEOUT = int(os.environ.get("REQUEST_TIMEOUT", "30"))
AUTH_TIMEOUT = int(os.environ.get("AUTH_TIMEOUT", "30"))
TIMESTAMP_DRIFT = int(os.environ.get("TIMESTAMP_DRIFT", "300"))

ETH_RPC_URL = os.environ.get("ETH_RPC_URL", "http://10.0.3.20:8545")
DEVICEPASS_CONTRACT = os.environ.get(
    "DEVICEPASS_CONTRACT", "0x5FbDB2315678afecb367f032d93F642f64180aa3"
)

POLL_COMMANDS = [
    {"method": "GET", "path": "/containers"},
    {"method": "GET", "path": "/skills"},
    {"method": "GET", "path": "/status"},
    {"method": "GET", "path": "/daemons"},
]

WS_MAGIC = b"258EAFA5-E914-47DA-95CA-5AB9FFE11246"

# --- Logging ---


def log(msg):
    print(f"hub: {msg}", flush=True)


def log_err(msg):
    print(f"hub: ERROR: {msg}", flush=True)


# --- Keccak-256 (Ethereum variant, NOT NIST SHA-3) ---
# Padding byte 0x01 (original Keccak), not 0x06 (NIST SHA-3).

try:
    from Crypto.Hash import keccak as _pycryptodome_keccak

    def keccak256(data):
        """Keccak-256 using pycryptodome."""
        if isinstance(data, str):
            data = data.encode()
        k = _pycryptodome_keccak.new(digest_bits=256)
        k.update(data)
        return k.digest()

    log("crypto: using pycryptodome Keccak")
except ImportError:
    # Pure-Python Keccak-256 fallback (Keccak-f[1600] sponge)
    def _keccak_f1600(state):
        RC = [
            0x0000000000000001, 0x0000000000008082, 0x800000000000808A,
            0x8000000080008000, 0x000000000000808B, 0x0000000080000001,
            0x8000000080008081, 0x8000000000008009, 0x000000000000008A,
            0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
            0x000000008000808B, 0x800000000000008B, 0x8000000000008089,
            0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
            0x000000000000800A, 0x800000008000000A, 0x8000000080008081,
            0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
        ]
        ROT = [
            [0, 1, 62, 28, 27], [36, 44, 6, 55, 20], [3, 10, 43, 25, 39],
            [41, 45, 15, 21, 8], [18, 2, 61, 56, 14],
        ]
        M = (1 << 64) - 1
        for rc in RC:
            # theta
            C = [state[x][0] ^ state[x][1] ^ state[x][2] ^ state[x][3] ^ state[x][4] for x in range(5)]
            D = [C[(x - 1) % 5] ^ (((C[(x + 1) % 5] << 1) | (C[(x + 1) % 5] >> 63)) & M) for x in range(5)]
            for x in range(5):
                for y in range(5):
                    state[x][y] ^= D[x]
            # rho + pi
            B = [[0] * 5 for _ in range(5)]
            for x in range(5):
                for y in range(5):
                    r = ROT[x][y]
                    B[y][(2 * x + 3 * y) % 5] = ((state[x][y] << r) | (state[x][y] >> (64 - r))) & M if r else state[x][y]
            # chi
            for x in range(5):
                for y in range(5):
                    state[x][y] = B[x][y] ^ ((~B[(x + 1) % 5][y] & M) & B[(x + 2) % 5][y])
            # iota
            state[0][0] ^= rc

    def keccak256(data):
        """Pure-Python Keccak-256 (Ethereum variant)."""
        if isinstance(data, str):
            data = data.encode()
        rate = 136  # (1600 - 256*2) / 8
        # Pad: append 0x01, zeros, then 0x80
        pad_len = rate - (len(data) % rate)
        if pad_len == 0:
            pad_len = rate
        padded = bytearray(data)
        padded.append(0x01)
        padded.extend(b'\x00' * (pad_len - 2))
        padded.append(0x80)
        # If pad_len == 1, first and last byte overlap
        if pad_len == 1:
            padded[-1] = 0x81
            # Redo properly
            padded = bytearray(data)
            padded.append(0x81)
        elif pad_len == 1:
            pass
        # Actually redo padding correctly
        padded = bytearray(data)
        q = rate - (len(data) % rate)
        if q == 1:
            padded.append(0x81)
        else:
            padded.append(0x01)
            padded.extend(b'\x00' * (q - 2))
            padded.append(0x80)
        # Absorb
        state = [[0] * 5 for _ in range(5)]
        for blk_off in range(0, len(padded), rate):
            block = padded[blk_off:blk_off + rate]
            for i in range(len(block) // 8):
                x, y = i % 5, i // 5
                state[x][y] ^= int.from_bytes(block[i*8:(i+1)*8], 'little')
            _keccak_f1600(state)
        # Squeeze 32 bytes
        out = b''
        for y in range(5):
            for x in range(5):
                out += state[x][y].to_bytes(8, 'little')
        return out[:32]

    log("crypto: using pure-Python Keccak (pycryptodome not available)")


# --- secp256k1 ecrecover (pure Python) ---

# secp256k1 curve parameters
_P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
_Gx = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
_Gy = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8


def _modinv(a, m):
    """Modular inverse via extended Euclidean algorithm."""
    if a < 0:
        a = a % m
    g, x, _ = _extended_gcd(a, m)
    if g != 1:
        raise ValueError("no inverse")
    return x % m


def _extended_gcd(a, b):
    if a == 0:
        return b, 0, 1
    g, x, y = _extended_gcd(b % a, a)
    return g, y - (b // a) * x, x


def _ec_add(p1, p2):
    """Add two points on secp256k1."""
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    x1, y1 = p1
    x2, y2 = p2
    if x1 == x2 and y1 == y2:
        # Point doubling
        lam = (3 * x1 * x1 * _modinv(2 * y1, _P)) % _P
    elif x1 == x2:
        return None  # point at infinity
    else:
        lam = ((y2 - y1) * _modinv(x2 - x1, _P)) % _P
    x3 = (lam * lam - x1 - x2) % _P
    y3 = (lam * (x1 - x3) - y1) % _P
    return (x3, y3)


def _ec_mul(point, scalar):
    """Scalar multiplication on secp256k1."""
    result = None
    addend = point
    while scalar:
        if scalar & 1:
            result = _ec_add(result, addend)
        addend = _ec_add(addend, addend)
        scalar >>= 1
    return result


def ecrecover(msg_hash, signature):
    """
    Recover Ethereum address from EIP-191 signature.
    msg_hash: 32-byte hash
    signature: 65-byte signature (r[32] + s[32] + v[1])
    Returns lowercase 0x-prefixed address or None.
    """
    if len(msg_hash) != 32 or len(signature) != 65:
        return None

    r = int.from_bytes(signature[:32], 'big')
    s = int.from_bytes(signature[32:64], 'big')
    v = signature[64]

    # Normalize v: accept both {0,1} and {27,28}
    if v >= 27:
        v -= 27
    if v not in (0, 1):
        return None

    if r == 0 or s == 0 or r >= _N or s >= _N:
        return None

    z = int.from_bytes(msg_hash, 'big')

    # Recover R point from r and v
    x = r
    # y^2 = x^3 + 7 mod p
    y_sq = (pow(x, 3, _P) + 7) % _P
    y = pow(y_sq, (_P + 1) // 4, _P)
    if (y * y) % _P != y_sq:
        return None
    if y % 2 != v:
        y = _P - y
    R = (x, y)

    # pubkey = r^-1 * (s*R - z*G)
    r_inv = _modinv(r, _N)
    u1 = (-z * r_inv) % _N
    u2 = (s * r_inv) % _N
    point = _ec_add(_ec_mul((_Gx, _Gy), u1), _ec_mul(R, u2))
    if point is None:
        return None

    # Uncompressed pubkey -> keccak256 -> last 20 bytes
    pubkey_bytes = point[0].to_bytes(32, 'big') + point[1].to_bytes(32, 'big')
    addr_hash = keccak256(pubkey_bytes)
    return "0x" + addr_hash[12:].hex()


def eth_signed_message_hash(msg_hash):
    """Compute EIP-191 personal sign hash: keccak256("\\x19Ethereum Signed Message:\\n32" + hash)"""
    prefix = b"\x19Ethereum Signed Message:\n32"
    return keccak256(prefix + msg_hash)


# --- On-chain passport lookup via JSON-RPC ---

_passport_cache = {}  # address -> (timestamp, passport_data)
PASSPORT_CACHE_TTL = 300  # 5 minutes


def _eth_call(to, data):
    """Execute eth_call via JSON-RPC. Returns hex result or None."""
    parsed = urlparse(ETH_RPC_URL)
    host = parsed.hostname
    port = parsed.port or 80

    payload = json.dumps({
        "jsonrpc": "2.0",
        "method": "eth_call",
        "params": [{"to": to, "data": data}, "latest"],
        "id": 1,
    })

    try:
        conn = http.client.HTTPConnection(host, port, timeout=10)
        conn.request("POST", parsed.path or "/", payload,
                     {"Content-Type": "application/json"})
        resp = conn.getresponse()
        body = json.loads(resp.read().decode())
        conn.close()
        result = body.get("result")
        if result and result != "0x":
            return result
        return None
    except Exception as e:
        log_err(f"eth_call failed: {e}")
        return None


def query_passport(device_address):
    """
    Query DevicePassRegistry.passports(address).
    Returns dict {device, guardian, created_at, active} or None.
    Uses TTL cache.
    """
    addr_lower = device_address.lower()
    now = time.time()

    cached = _passport_cache.get(addr_lower)
    if cached and (now - cached[0]) < PASSPORT_CACHE_TTL:
        return cached[1]

    # passports(address) selector: keccak256("passports(address)")[:4]
    # = 0xe37c132b (from compiled contract ABI)
    selector = "e37c132b"
    # ABI-encode address: pad to 32 bytes
    addr_hex = addr_lower[2:] if addr_lower.startswith("0x") else addr_lower
    padded = addr_hex.zfill(64)
    calldata = "0x" + selector + padded

    result = _eth_call(DEVICEPASS_CONTRACT, calldata)
    if not result:
        _passport_cache[addr_lower] = (now, None)
        return None

    # Decode: (address device, address guardian, uint256 createdAt, bool active)
    # Each field is 32 bytes (64 hex chars), result starts with "0x"
    hex_data = result[2:]
    if len(hex_data) < 256:  # 4 * 64
        _passport_cache[addr_lower] = (now, None)
        return None

    device = "0x" + hex_data[24:64]   # address in last 20 bytes of slot
    guardian = "0x" + hex_data[88:128]
    created_at = int(hex_data[128:192], 16)
    active = int(hex_data[192:256], 16) != 0

    if created_at == 0:
        # Not claimed
        _passport_cache[addr_lower] = (now, None)
        return None

    passport = {
        "device": device.lower(),
        "guardian": guardian.lower(),
        "created_at": created_at,
        "active": active,
    }
    _passport_cache[addr_lower] = (now, passport)
    return passport


def invalidate_passport_cache(address=None):
    """Clear passport cache, optionally for a single address."""
    if address:
        _passport_cache.pop(address.lower(), None)
    else:
        _passport_cache.clear()


# --- WebSocket helpers ---


def ws_accept_key(client_key):
    digest = hashlib.sha1(client_key.encode() + WS_MAGIC).digest()
    return base64.b64encode(digest).decode()


def ws_encode_frame(payload):
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


# --- Device Registry (keyed by Ethereum address) ---


class DeviceRegistry:

    def __init__(self):
        self._devices = {}

    def register(self, address, guardian, writer):
        """Register a device by Ethereum address. Replaces existing connection."""
        addr = address.lower()
        existing = self._devices.get(addr)
        if existing and existing["online"]:
            # Close old connection
            for fut in existing["pending_requests"].values():
                if not fut.done():
                    fut.set_exception(ConnectionError("replaced by new connection"))
            existing["pending_requests"].clear()
            existing["online"] = False

        self._devices[addr] = {
            "id": addr,
            "address": addr,
            "guardian": guardian.lower(),
            "online": True,
            "connected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "last_heartbeat": None,
            "containers": None,
            "skills": None,
            "status": None,
            "daemons": None,
            "ws_writer": writer,
            "pending_requests": {},
            "req_counter": 0,
        }
        return addr

    def unregister(self, dev_id):
        dev = self._devices.get(dev_id)
        if dev:
            dev["online"] = False
            dev["ws_writer"] = None
            for fut in dev["pending_requests"].values():
                if not fut.done():
                    fut.set_exception(ConnectionError("device disconnected"))
            dev["pending_requests"].clear()

    def get(self, dev_id):
        return self._devices.get(dev_id.lower() if dev_id else dev_id)

    def list_all(self):
        return list(self._devices.values())

    def list_online(self):
        return [d for d in self._devices.values() if d["online"]]

    def list_by_guardian(self, guardian):
        """List devices owned by a specific guardian."""
        g = guardian.lower()
        return [d for d in self._devices.values() if d.get("guardian") == g]

    def next_req_id(self, dev_id):
        dev = self._devices.get(dev_id)
        if not dev:
            return None
        dev["req_counter"] += 1
        return f"hub-{dev_id[:10]}-{dev['req_counter']}"

    def to_json(self, dev):
        return {
            "id": dev["id"],
            "address": dev["address"],
            "guardian": dev["guardian"],
            "online": dev["online"],
            "connected_at": dev["connected_at"],
            "last_heartbeat": dev["last_heartbeat"],
            "containers": dev["containers"],
            "skills": dev["skills"],
            "status": dev["status"],
            "daemons": dev["daemons"],
            "pending_count": len(dev["pending_requests"]),
        }


registry = DeviceRegistry()

# --- WebSocket tunnel ---


async def send_ws_request(dev, method, path, body=None):
    if not dev["online"] or not dev["ws_writer"]:
        raise ConnectionError("device not connected")

    req_id = registry.next_req_id(dev["id"])
    msg = json.dumps({
        "id": req_id,
        "method": method,
        "path": path,
        "body": body,
    })

    fut = asyncio.get_event_loop().create_future()
    dev["pending_requests"][req_id] = fut

    try:
        frame = ws_encode_frame(msg)
        dev["ws_writer"].write(frame)
        await dev["ws_writer"].drain()
        log(f"[device {dev['id'][:10]}] sent {method} {path} (id={req_id})")
        return await asyncio.wait_for(fut, timeout=REQUEST_TIMEOUT)
    except asyncio.TimeoutError:
        log_err(f"[device {dev['id'][:10]}] request {req_id} timed out")
        raise
    finally:
        dev["pending_requests"].pop(req_id, None)


async def poll_device(dev):
    dev_id = dev["id"]
    poll_idx = 0

    while dev["online"]:
        await asyncio.sleep(POLL_INTERVAL)
        if not dev["online"]:
            break

        cmd = POLL_COMMANDS[poll_idx % len(POLL_COMMANDS)]
        poll_idx += 1

        try:
            resp = await send_ws_request(dev, cmd["method"], cmd["path"])
            status = resp.get("status", "?")
            body = resp.get("body")

            if status == 200 and body is not None:
                path_key = cmd["path"].lstrip("/")
                dev[path_key] = body
                dev["last_heartbeat"] = time.strftime(
                    "%Y-%m-%dT%H:%M:%SZ", time.gmtime()
                )

            body_preview = json.dumps(body)[:200] if body else "null"
            log(f"[device {dev_id[:10]}] poll {cmd['path']} -> {status} {body_preview}")
        except (ConnectionError, asyncio.TimeoutError):
            break
        except Exception as e:
            log_err(f"[device {dev_id[:10]}] poll error: {e}")
            break


async def ws_read_json(reader, writer, buf, timeout):
    """Read next WebSocket text frame as JSON. Returns (parsed_dict, remaining_buf) or raises."""
    deadline = time.time() + timeout
    while True:
        remaining = deadline - time.time()
        if remaining <= 0:
            raise asyncio.TimeoutError("auth timeout")

        # Try to decode a frame from buffer
        result = ws_decode_frame(buf)
        if result is not None:
            opcode, payload, consumed = result
            buf = buf[consumed:]
            if opcode == 0x08:
                raise ConnectionError("close frame during auth")
            if opcode == 0x09:  # ping
                writer.write(bytes(bytearray([0x8A, 0x00])))
                await writer.drain()
                continue
            if opcode == 0x0A:  # pong
                continue
            return json.loads(payload.decode()), buf

        chunk = await asyncio.wait_for(reader.read(65536), timeout=remaining)
        if not chunk:
            raise ConnectionError("connection closed during auth")
        buf += chunk


async def handle_ws_connection(reader, writer, headers):
    """Handle WebSocket upgrade, device authentication, and tunnel session."""
    ws_key = headers.get("sec-websocket-key")
    if not ws_key:
        log_err("no WebSocket key in upgrade request")
        writer.write(http_response(400, {"error": "missing Sec-WebSocket-Key"}))
        await writer.drain()
        writer.close()
        return

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

    # --- Authentication phase ---
    # Send challenge
    challenge = os.urandom(32).hex()
    challenge_msg = json.dumps({
        "type": "auth_challenge",
        "challenge": challenge,
    })
    writer.write(ws_encode_frame(challenge_msg))
    await writer.drain()
    log("[auth] sent challenge")

    buf = b""
    try:
        # Wait for auth_response
        auth_resp, buf = await ws_read_json(reader, writer, buf, AUTH_TIMEOUT)

        if auth_resp.get("type") != "auth_response":
            log_err(f"[auth] expected auth_response, got {auth_resp.get('type')}")
            writer.write(ws_encode_frame(json.dumps({
                "type": "auth_result",
                "status": "rejected",
                "message": "expected auth_response",
            })))
            await writer.drain()
            writer.close()
            return

        claimed_address = auth_resp.get("address", "").lower()
        sig_hex = auth_resp.get("signature", "")

        if not claimed_address or not sig_hex:
            log_err("[auth] missing address or signature")
            writer.write(ws_encode_frame(json.dumps({
                "type": "auth_result",
                "status": "rejected",
                "message": "missing address or signature",
            })))
            await writer.drain()
            writer.close()
            return

        # Verify signature
        # Device signs: keccak256("\x19Ethereum Signed Message:\n32" + keccak256(challenge_bytes))
        challenge_bytes = bytes.fromhex(challenge)
        challenge_hash = keccak256(challenge_bytes)
        msg_hash = eth_signed_message_hash(challenge_hash)

        sig_bytes = bytes.fromhex(sig_hex.replace("0x", ""))
        recovered = ecrecover(msg_hash, sig_bytes)

        if not recovered or recovered.lower() != claimed_address:
            log_err(f"[auth] signature mismatch: recovered={recovered}, claimed={claimed_address}")
            writer.write(ws_encode_frame(json.dumps({
                "type": "auth_result",
                "status": "rejected",
                "message": "signature verification failed",
            })))
            await writer.drain()
            writer.close()
            return

        log(f"[auth] signature verified for {claimed_address}")

        # Query on-chain passport
        passport = query_passport(claimed_address)
        if not passport:
            log(f"[auth] device {claimed_address} not claimed on-chain")
            writer.write(ws_encode_frame(json.dumps({
                "type": "auth_result",
                "status": "not_claimed",
                "message": "device not found in DevicePassRegistry",
            })))
            await writer.drain()
            writer.close()
            return

        if not passport["active"]:
            log(f"[auth] device {claimed_address} passport revoked")
            writer.write(ws_encode_frame(json.dumps({
                "type": "auth_result",
                "status": "rejected",
                "message": "device passport is revoked",
            })))
            await writer.drain()
            writer.close()
            return

        guardian = passport["guardian"]
        log(f"[auth] device {claimed_address} authenticated, guardian: {guardian}")

        # Send success
        writer.write(ws_encode_frame(json.dumps({
            "type": "auth_result",
            "status": "ok",
            "guardian": guardian,
        })))
        await writer.drain()

    except (asyncio.TimeoutError, ConnectionError) as e:
        log_err(f"[auth] failed: {e}")
        writer.close()
        return
    except Exception as e:
        log_err(f"[auth] error: {e}")
        traceback.print_exc()
        writer.close()
        return

    # --- Authenticated session ---
    dev_id = registry.register(claimed_address, guardian, writer)
    dev = registry.get(dev_id)
    log(f"[device {dev_id[:10]}] authenticated and registered")

    poll_task = asyncio.ensure_future(poll_device(dev))

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
                    log(f"[device {dev_id[:10]}] close frame")
                    return

                if opcode == 0x09:  # ping
                    pong = bytearray([0x8A, 0x00])
                    writer.write(bytes(pong))
                    await writer.drain()
                    continue

                if opcode == 0x0A:  # pong
                    continue

                try:
                    resp = json.loads(payload.decode())
                    req_id = resp.get("id", "?")
                    fut = dev["pending_requests"].get(req_id)
                    if fut and not fut.done():
                        fut.set_result(resp)
                    else:
                        log(f"[device {dev_id[:10]}] unsolicited response id={req_id}")
                except json.JSONDecodeError:
                    log_err(f"[device {dev_id[:10]}] invalid JSON: {payload[:100]}")
    except asyncio.CancelledError:
        pass
    except Exception as e:
        log_err(f"[device {dev_id[:10]}] read error: {e}")
    finally:
        poll_task.cancel()
        registry.unregister(dev_id)
        writer.close()
        log(f"[device {dev_id[:10]}] disconnected")


# --- Guardian authentication ---


def authenticate_guardian(headers):
    """
    Authenticate guardian from REST request headers.
    Returns (guardian_address, None) on success, or (None, error_response_tuple) on failure.
    """
    guardian = headers.get("x-devicepass-guardian", "").lower()
    timestamp_str = headers.get("x-devicepass-timestamp", "")
    sig_hex = headers.get("x-devicepass-signature", "")

    if not guardian or not timestamp_str or not sig_hex:
        return None, (401, {"error": "missing authentication headers"})

    # Check timestamp drift
    try:
        timestamp = int(timestamp_str)
    except ValueError:
        return None, (401, {"error": "invalid timestamp"})

    drift = abs(int(time.time()) - timestamp)
    if drift > TIMESTAMP_DRIFT:
        return None, (401, {"error": f"timestamp drift too large ({drift}s)"})

    # Recover signer from signature
    # Signed message: keccak256("\x19Ethereum Signed Message:\n32" + keccak256(method + path + timestamp))
    method = headers.get("_method", "GET")
    path = headers.get("_path", "/")
    sign_data = (method + path + timestamp_str).encode()
    data_hash = keccak256(sign_data)
    msg_hash = eth_signed_message_hash(data_hash)

    sig_bytes = bytes.fromhex(sig_hex.replace("0x", ""))
    recovered = ecrecover(msg_hash, sig_bytes)

    if not recovered or recovered.lower() != guardian:
        return None, (403, {"error": "signature verification failed"})

    return guardian, None


# --- REST API ---


class HTTPRequest:
    def __init__(self, method, path, headers, body):
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body


def http_response(status, body=None, content_type="application/json"):
    status_text = {
        200: "OK",
        400: "Bad Request",
        401: "Unauthorized",
        403: "Forbidden",
        404: "Not Found",
        408: "Request Timeout",
        500: "Internal Server Error",
        502: "Bad Gateway",
        503: "Service Unavailable",
    }.get(status, "Unknown")

    if body is None:
        body_bytes = b""
    elif isinstance(body, (dict, list)):
        body_bytes = json.dumps(body, indent=2).encode()
    elif isinstance(body, str):
        body_bytes = body.encode()
    else:
        body_bytes = body

    resp = (
        f"HTTP/1.1 {status} {status_text}\r\n"
        f"Content-Type: {content_type}\r\n"
        f"Content-Length: {len(body_bytes)}\r\n"
        f"Connection: close\r\n"
        f"\r\n"
    )
    return resp.encode() + body_bytes


def match_route(method, path, pattern_method, pattern):
    if method != pattern_method:
        return None

    path_parts = path.strip("/").split("/")
    pattern_parts = pattern.strip("/").split("/")

    if len(path_parts) != len(pattern_parts):
        return None

    params = {}
    for pp, pat in zip(path_parts, pattern_parts):
        if pat.startswith("{") and pat.endswith("}"):
            params[pat[1:-1]] = pp
        elif pp != pat:
            return None

    return params


async def handle_api_request(req):
    """Route and handle a REST API request."""

    # GET /v1/health (unauthenticated)
    params = match_route(req.method, req.path, "GET", "/v1/health")
    if params is not None:
        online = registry.list_online()
        return 200, {
            "status": "ok",
            "devices_online": len(online),
            "devices_total": len(registry.list_all()),
            "uptime_seconds": int(time.time() - _start_time),
        }

    # All other endpoints require guardian authentication
    # Stash method/path in headers for signature verification
    req.headers["_method"] = req.method
    req.headers["_path"] = req.path
    guardian, err = authenticate_guardian(req.headers)
    if err:
        return err

    # GET /v1/devices (filtered by guardian)
    params = match_route(req.method, req.path, "GET", "/v1/devices")
    if params is not None:
        devices = registry.list_by_guardian(guardian)
        return 200, {
            "devices": [registry.to_json(d) for d in devices],
        }

    # GET /v1/devices/{id}
    params = match_route(req.method, req.path, "GET", "/v1/devices/{id}")
    if params is not None:
        dev = registry.get(params["id"])
        if not dev:
            return 404, {"error": f"device {params['id']} not found"}
        if dev.get("guardian") != guardian:
            return 403, {"error": "not your device"}
        return 200, registry.to_json(dev)

    # POST /v1/devices/{id}/call
    params = match_route(req.method, req.path, "POST", "/v1/devices/{id}/call")
    if params is not None:
        dev = registry.get(params["id"])
        if not dev:
            return 404, {"error": f"device {params['id']} not found"}
        if dev.get("guardian") != guardian:
            return 403, {"error": "not your device"}
        if not dev["online"]:
            return 503, {"error": f"device {params['id']} is offline"}

        if not isinstance(req.body, dict):
            return 400, {"error": "body must be JSON with 'method' and 'path'"}

        method = req.body.get("method", "GET")
        path = req.body.get("path", "/")
        body = req.body.get("body")

        try:
            resp = await send_ws_request(dev, method, path, body)
            return 200, {
                "device_id": dev["id"],
                "response": resp,
            }
        except asyncio.TimeoutError:
            return 408, {"error": "device request timed out"}
        except ConnectionError as e:
            return 502, {"error": str(e)}

    # POST /v1/devices/group/call
    params = match_route(req.method, req.path, "POST", "/v1/devices/group/call")
    if params is not None:
        if not isinstance(req.body, dict):
            return 400, {"error": "body must be JSON with 'devices', 'method', 'path'"}

        target_devices = req.body.get("devices", ["all"])
        method = req.body.get("method", "GET")
        path = req.body.get("path", "/")
        body = req.body.get("body")

        guardian_devices = registry.list_by_guardian(guardian)
        if "all" in target_devices:
            targets = [d for d in guardian_devices if d["online"]]
        else:
            targets = []
            for did in target_devices:
                dev = registry.get(did)
                if dev and dev["online"] and dev.get("guardian") == guardian:
                    targets.append(dev)

        if not targets:
            return 200, {"results": {}}

        async def call_device(dev):
            try:
                resp = await send_ws_request(dev, method, path, body)
                return dev["id"], {"response": resp}
            except asyncio.TimeoutError:
                return dev["id"], {"error": "timeout"}
            except ConnectionError as e:
                return dev["id"], {"error": str(e)}

        results = await asyncio.gather(*[call_device(d) for d in targets])
        return 200, {"results": dict(results)}

    return 404, {"error": f"not found: {req.method} {req.path}"}


async def handle_rest_connection(reader, writer, method, path, headers, remainder):
    """Handle a REST API request after HTTP headers are parsed."""
    try:
        body = None
        content_length = int(headers.get("content-length", "0"))
        if content_length > 0:
            body_data = remainder
            while len(body_data) < content_length:
                chunk = await reader.read(content_length - len(body_data))
                if not chunk:
                    break
                body_data += chunk
            try:
                body = json.loads(body_data.decode())
            except (json.JSONDecodeError, UnicodeDecodeError):
                body = body_data.decode(errors="replace")

        req = HTTPRequest(method, path, headers, body)
        log(f"[api] {req.method} {req.path}")
        status, resp_body = await handle_api_request(req)
        writer.write(http_response(status, resp_body))
        await writer.drain()
    except Exception as e:
        log_err(f"[api] handler error: {e}")
        traceback.print_exc()
        try:
            writer.write(http_response(500, {"error": "internal server error"}))
            await writer.drain()
        except Exception:
            pass
    finally:
        writer.close()


# --- Connection dispatcher ---


async def handle_connection(reader, writer):
    """Accept a TCP connection and route based on HTTP request."""
    try:
        # Read HTTP headers
        header_data = b""
        while b"\r\n\r\n" not in header_data:
            chunk = await reader.read(4096)
            if not chunk:
                writer.close()
                return
            header_data += chunk

        header_end = header_data.index(b"\r\n\r\n")
        header_str = header_data[:header_end].decode(errors="replace")
        remainder = header_data[header_end + 4:]

        lines = header_str.split("\r\n")
        if not lines:
            writer.close()
            return

        # Parse request line
        parts = lines[0].split(" ", 2)
        if len(parts) < 2:
            writer.close()
            return
        method = parts[0]
        path = parts[1]

        # Parse headers
        headers = {}
        for line in lines[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()

        # Route: WebSocket upgrade to /tunnel -> tunnel handler
        upgrade = headers.get("upgrade", "").lower()
        if upgrade == "websocket" and path == "/tunnel":
            await handle_ws_connection(reader, writer, headers)
        else:
            await handle_rest_connection(
                reader, writer, method, path, headers, remainder
            )
    except Exception as e:
        log_err(f"connection error: {e}")
        traceback.print_exc()
        writer.close()


# --- Main ---

_start_time = time.time()


async def main():
    log("starting DevicePass Hub (authenticated)")
    log(f"listening on {HUB_HOST}:{HUB_PORT}")
    log(f"poll interval: {POLL_INTERVAL}s, request timeout: {REQUEST_TIMEOUT}s")
    log(f"ETH RPC: {ETH_RPC_URL}, contract: {DEVICEPASS_CONTRACT}")

    # Verify contract is reachable (non-fatal)
    passport = query_passport("0x0000000000000000000000000000000000000000")
    if passport is None:
        log("contract check: OK (zero address not claimed, as expected)")
    else:
        log("contract check: WARNING (zero address has passport?)")

    server = await asyncio.start_server(
        handle_connection, HUB_HOST, HUB_PORT
    )
    log("hub ready")

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log("shutting down")
