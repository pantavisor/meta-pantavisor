# DevicePass Test Plans

This document provides executable test plans for validating the devicepass system: device identity (Phase 1), smart contract (Phase 2), guardian CLI (Phase 3), and the pv-devicepass management container in the appengine environment.

**Branch**: `feature/devicepass-phase1`

## Prerequisites

### Foundry (Forge, Cast, Anvil)

Required for smart contract tests and on-chain interaction.

```bash
# Install (one-time)
curl -L https://foundry.paradigm.xyz | bash
~/.foundry/bin/foundryup

# Verify
~/.foundry/bin/forge --version
~/.foundry/bin/cast --version
~/.foundry/bin/anvil --version
```

Add to PATH for convenience:

```bash
export PATH="$HOME/.foundry/bin:$PATH"
```

### Build Appengine Image

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

### Build DevicePass Container

```bash
./kas-container shell .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    -c "bitbake pantavisor -c install -f && bitbake pv-devicepass-container"

cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-devicepass-container.pvrexport.tgz pvtx.d/
```

### Common Appengine Setup

```bash
docker rm -f pva-test 2>/dev/null
docker volume rm storage-test 2>/dev/null
mkdir -p pvtx.d

docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Common Teardown

```bash
docker rm -f pva-test
docker volume rm storage-test
```

### Contracts Directory

All contract commands run from:

```bash
cd build/workspace/sources/pantavisor/pv-devicepass/contracts
```

---

## Test 1: Keccak-256 Test Vectors

**Purpose**: Verify the keccak256sum binary produces correct Ethereum-compatible Keccak-256 hashes (NOT NIST SHA-3).

### Host-side (native compile)

```bash
cd build/workspace/sources/pantavisor/pv-devicepass
gcc -o /tmp/keccak256sum keccak256sum.c -Wall -Wextra

# Empty string
echo -n "" | /tmp/keccak256sum
# Expected: c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470

# "hello"
echo -n "hello" | /tmp/keccak256sum
# Expected: 1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8

# Hex input mode (hash of 0xdeadbeef = 4 bytes)
echo -n "deadbeef" | /tmp/keccak256sum --hex
# Expected: d4fd4e189132273036449fc9e11198c739161b4c0116a9a2dccdfa1c492006f1
```

### In-container

```bash
docker exec pva-test pventer -c pv-devicepass-container keccak256sum --help
# Expected: Usage line
```

### Expected Results

| Input | Expected Hash |
|-------|---------------|
| `""` (empty) | `c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470` |
| `"hello"` | `1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8` |
| `0xdeadbeef` (--hex) | `d4fd4e189132273036449fc9e11198c739161b4c0116a9a2dccdfa1c492006f1` |

---

## Test 2: Device Identity Generation

**Purpose**: Verify `devicepass-cli init` generates a valid secp256k1 keypair, derives a correct Ethereum address, and stores identity files.

### Execute

```bash
docker exec pva-test pventer -c pv-devicepass-container devicepass-cli init
```

### Verify

```bash
# Check identity files exist
docker exec pva-test pventer -c pv-devicepass-container ls -la /var/lib/devicepass/
# Expected: device.key (600 permissions), device.pub.hex, device.address, device.id

# Check address format (0x + 40 hex chars)
docker exec pva-test pventer -c pv-devicepass-container cat /var/lib/devicepass/device.address
# Expected: 0x followed by 40 hex characters

# Check device ID format (dp- + 12 hex chars)
docker exec pva-test pventer -c pv-devicepass-container cat /var/lib/devicepass/device.id
# Expected: dp- followed by 12 hex chars matching the address prefix

# Check public key is 128 hex chars (64 bytes, x||y, no 04 prefix)
docker exec pva-test pventer -c pv-devicepass-container cat /var/lib/devicepass/device.pub.hex
# Expected: 128 hex characters

# Verify address derivation: keccak256(pubkey) → last 40 hex chars
PUBHEX=$(docker exec pva-test pventer -c pv-devicepass-container cat /var/lib/devicepass/device.pub.hex 2>/dev/null | grep -v '^export')
HASH=$(echo -n "$PUBHEX" | /tmp/keccak256sum --hex)
ADDR_FROM_HASH=$(echo "$HASH" | tail -c 41 | head -c 40)
ADDR_FILE=$(docker exec pva-test pventer -c pv-devicepass-container cat /var/lib/devicepass/device.address 2>/dev/null | grep '0x' | sed 's/0x//')
echo "Derived:  $ADDR_FROM_HASH"
echo "On file:  $ADDR_FILE"
# Expected: both match

# Status command
docker exec pva-test pventer -c pv-devicepass-container devicepass-cli status
# Expected: Shows Address, ID, Chain ID, Contract, Key dir

# Reinit should fail without --force
docker exec pva-test pventer -c pv-devicepass-container devicepass-cli init
# Expected: "Identity already exists" warning, exit 1
```

### Expected Results

| Check | Expected |
|-------|----------|
| device.key permissions | 600 |
| device.address format | `0x` + 40 hex chars |
| device.id format | `dp-` + first 12 chars of address |
| device.pub.hex length | 128 hex chars |
| Address derivation | keccak256(pub) last 40 chars = address |
| Reinit without --force | Rejected |

---

## Test 3: Onboard Claim Blob

**Purpose**: Verify `devicepass-cli onboard` produces a valid signed claim JSON blob that can be verified independently.

### Execute

```bash
docker exec pva-test pventer -c pv-devicepass-container devicepass-cli onboard --quiet
# Expected: JSON blob like:
# {"version":1,"device":"0x...","nonce":TIMESTAMP,"chain_id":8453,"contract":"0x...","signature":"0x..."}
```

### Verify

```bash
# Capture the claim
CLAIM=$(docker exec pva-test pventer -c pv-devicepass-container devicepass-cli onboard --quiet 2>/dev/null | grep '^{')
echo "$CLAIM" | python3 -m json.tool
# Expected: valid JSON with all fields

# Check signature length (0x + 130 hex chars = 65 bytes = r:32 + s:32 + v:1)
SIG=$(echo "$CLAIM" | python3 -c "import sys,json; print(json.load(sys.stdin)['signature'])")
echo "Signature: $SIG"
echo "Length: ${#SIG}"
# Expected: 132 characters (0x + 130 hex)

# Check v value is 1b (27) or 1c (28)
V=${SIG: -2}
echo "v = 0x$V"
# Expected: 1b or 1c
```

### Expected Results

| Check | Expected |
|-------|----------|
| Output format | Valid JSON |
| version | 1 |
| device | Matches device.address |
| nonce | Unix timestamp (reasonable value) |
| chain_id | 8453 (default) |
| signature | 0x + 130 hex chars |
| v byte | 0x1b (27) or 0x1c (28) |

---

## Test 4: Smart Contract — Unit Tests

**Purpose**: Verify the DevicePassRegistry contract logic using Forge's built-in test framework.

### Execute

```bash
cd build/workspace/sources/pantavisor/pv-devicepass/contracts

forge test -vv
```

### Expected Results

```
[PASS] test_claimDevice()
[PASS] test_claimDevice_emitsEvent()
[PASS] test_claimDevice_revert_alreadyClaimed()
[PASS] test_claimDevice_revert_badSignatureLength()
[PASS] test_claimDevice_revert_nonceReplay()
[PASS] test_claimDevice_revert_wrongSigner()
[PASS] test_multipleDevicesPerGuardian()
[PASS] test_revokeDevice()
[PASS] test_revokeDevice_revert_alreadyRevoked()
[PASS] test_revokeDevice_revert_notGuardian()
[PASS] test_transferDevice()
[PASS] test_transferDevice_revert_notGuardian()
[PASS] test_transferDevice_revert_toSelf()
Suite result: ok. 13 passed; 0 failed; 0 skipped
```

### What the tests cover

| Test | Validates |
|------|-----------|
| `test_claimDevice` | Happy path: device sig verified, passport created, guardian recorded |
| `test_claimDevice_emitsEvent` | PassportCreated event emitted |
| `test_claimDevice_revert_alreadyClaimed` | Cannot claim an already-active device |
| `test_claimDevice_revert_nonceReplay` | Same nonce rejected even after revoke |
| `test_claimDevice_revert_wrongSigner` | Signature from wrong key rejected |
| `test_claimDevice_revert_badSignatureLength` | Non-65-byte signature rejected |
| `test_transferDevice` | Guardian can transfer ownership, device lists updated |
| `test_transferDevice_revert_notGuardian` | Only current guardian can transfer |
| `test_transferDevice_revert_toSelf` | Cannot transfer to yourself |
| `test_revokeDevice` | Guardian can deactivate a passport |
| `test_revokeDevice_revert_notGuardian` | Only guardian can revoke |
| `test_revokeDevice_revert_alreadyRevoked` | Cannot revoke twice |
| `test_multipleDevicesPerGuardian` | One guardian can claim multiple devices |

---

## Test 5: Anvil End-to-End — Deploy, Claim, Verify

**Purpose**: Full on-chain flow on a local Anvil testnet: deploy contract, claim a real running device, verify on-chain state.

### Start Anvil

```bash
# Ensure no other process on port 8546 (8545 may be used by hardhat sidecar)
anvil --chain-id 31337 --port 8546 --silent &
```

**Anvil pre-funded accounts** (for reference):

| Account | Address | Private Key |
|---------|---------|-------------|
| #0 (deployer) | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| #1 (guardian) | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |

### Deploy Contract

```bash
cd build/workspace/sources/pantavisor/pv-devicepass/contracts

forge script script/Deploy.s.sol \
    --rpc-url http://localhost:8546 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast
# Expected: "DevicePassRegistry deployed at: 0x5FbDB2315678afecb367f032d93F642f64180aa3"
```

> **Note**: The deploy address is deterministic on a fresh Anvil: `0x5FbDB2315678afecb367f032d93F642f64180aa3`. If Anvil was restarted clean, this address is always the same for the first deployment from account #0.

### Claim the Running Device

Extract the device key from the running container and claim it using the Forge script:

```bash
# Get device private key from running container
DEVICE_KEY=$(docker exec pva-test pventer -c pv-devicepass-container \
    cat /var/lib/devicepass/device.key 2>/dev/null | grep -v '^export')
echo "Device key: $DEVICE_KEY"

DEVICE_ADDR=$(docker exec pva-test pventer -c pv-devicepass-container \
    cat /var/lib/devicepass/device.address 2>/dev/null | grep '0x')
echo "Device address: $DEVICE_ADDR"

# Claim as guardian (Anvil account #1)
DEVICE_KEY="0x${DEVICE_KEY}" \
REGISTRY="0x5FbDB2315678afecb367f032d93F642f64180aa3" \
forge script script/Claim.s.sol \
    --rpc-url http://localhost:8546 \
    --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
    --broadcast

# Expected output:
#   Device: 0x<device_address>
#   Guardian: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
#   Nonce: <timestamp>
#   Claimed! Guardian: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
#   Active: true
```

### Verify On-Chain State

```bash
REGISTRY="0x5FbDB2315678afecb367f032d93F642f64180aa3"
RPC="http://localhost:8546"

# Query passport
cast call "$REGISTRY" \
    "passports(address)(address,address,uint256,bool)" \
    "$DEVICE_ADDR" --rpc-url "$RPC"
# Expected: device_addr, guardian_addr, timestamp, true

# Guardian device count
GUARDIAN="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
cast call "$REGISTRY" \
    "guardianDeviceCount(address)(uint256)" \
    "$GUARDIAN" --rpc-url "$RPC"
# Expected: 1

# Guardian device list
cast call "$REGISTRY" \
    "guardianDeviceAt(address,uint256)(address)" \
    "$GUARDIAN" 0 --rpc-url "$RPC"
# Expected: device_addr
```

### Test Transfer

```bash
# Transfer device from guardian #1 to Anvil account #2
NEW_GUARDIAN="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"

cast send "$REGISTRY" \
    "transferDevice(address,address)" \
    "$DEVICE_ADDR" "$NEW_GUARDIAN" \
    --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
    --rpc-url "$RPC"

# Verify new guardian
cast call "$REGISTRY" \
    "passports(address)(address,address,uint256,bool)" \
    "$DEVICE_ADDR" --rpc-url "$RPC"
# Expected: guardian field = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
```

### Test Revoke

```bash
# Revoke (now from new guardian, account #2)
cast send "$REGISTRY" \
    "revokeDevice(address)" \
    "$DEVICE_ADDR" \
    --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a \
    --rpc-url "$RPC"

# Verify revoked
cast call "$REGISTRY" \
    "passports(address)(address,address,uint256,bool)" \
    "$DEVICE_ADDR" --rpc-url "$RPC"
# Expected: active = false
```

### Teardown

```bash
# Stop Anvil
pkill -f "anvil.*8546"
```

### Expected Results

| Step | Expected |
|------|----------|
| Deploy | Contract at deterministic address |
| Claim | PassportCreated event, guardian recorded |
| passports() query | device, guardian, timestamp, active=true |
| guardianDeviceCount() | 1 |
| Transfer | Guardian field updated, old=0, new=1 |
| Revoke | active=false |

---

## Test 6: pv-devicepass HTTP API

**Purpose**: Verify pv-devicepass starts, exposes its HTTP API, and correctly proxies pv-ctrl endpoints (`/containers`, `/status`, `/skills`, `/daemons`).

### Setup

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-devicepass-container

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-devicepass-container.pvrexport.tgz pvtx.d/
```

### Execute

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Verify

```bash
# Check pv-devicepass container running
docker exec pva-test lxc-ls -f
# Expected: pv-devicepass-container RUNNING

# Check pv-devicepass logs — should show "listening on" and "entering event loop"
docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-devicepass-container/lxc/console.log
# Expected: "pv-devicepass v1.0 starting...", "listening on /run/pv-devicepass/api.sock", "entering event loop"

# GET /containers — proxy to pv-ctrl
docker exec pva-test pventer -c pv-devicepass-container \
    curl -s --unix-socket /run/pv-devicepass/api.sock http://localhost/containers | jq .
# Expected: JSON array of containers

# GET /status — proxy to pv-ctrl /buildinfo
docker exec pva-test pventer -c pv-devicepass-container \
    curl -s --unix-socket /run/pv-devicepass/api.sock http://localhost/status | jq .
# Expected: JSON with build info

# GET /skills — locally-built skills list
docker exec pva-test pventer -c pv-devicepass-container \
    curl -s --unix-socket /run/pv-devicepass/api.sock http://localhost/skills | jq .
# Expected: JSON array (may be empty if no REST services discovered yet)

# GET /daemons — proxy to pv-ctrl
docker exec pva-test pventer -c pv-devicepass-container \
    curl -s --unix-socket /run/pv-devicepass/api.sock http://localhost/daemons | jq .
# Expected: JSON array with daemon info

# 404 for unknown path
docker exec pva-test pventer -c pv-devicepass-container \
    curl -s -o /dev/null -w '%{http_code}' --unix-socket /run/pv-devicepass/api.sock http://localhost/nonexistent
# Expected: 404
```

### Expected Results

| Check | Expected |
|-------|----------|
| pv-devicepass-container status | RUNNING |
| Agent log | Shows "listening" and "entering event loop" |
| GET /containers | JSON array of containers |
| GET /status | JSON build info |
| GET /skills | JSON array |
| GET /daemons | JSON array with daemon info |
| GET /nonexistent | 404 |

---

## Test 7: pv-devicepass Service Proxy

**Purpose**: Verify pv-devicepass discovers REST services via xconnect-graph and proxies requests to provider containers with identity header injection.

### Setup

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-devicepass-container \
    --target pv-example-rest-server

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-devicepass-container.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-rest-server.pvrexport.tgz pvtx.d/
```

### Execute

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 20
```

### Verify

```bash
# Check both containers running
docker exec pva-test lxc-ls -f
# Expected: pv-devicepass-container RUNNING, pv-example-rest-server RUNNING

# Wait for graph polling to discover the REST service
sleep 10

# GET /skills — should show network-manager REST service
docker exec pva-test pventer -c pv-devicepass-container \
    curl -s --unix-socket /run/pv-devicepass/api.sock http://localhost/skills | jq .
# Expected: [{"name":"network-manager","type":"rest","provider_pid":...}]

# Proxy request to REST server via pv-devicepass
docker exec pva-test pventer -c pv-devicepass-container \
    curl -s --unix-socket /run/pv-devicepass/api.sock http://localhost/services/network-manager/ | jq .
# Expected: Response from rest-server (proxied through pv-devicepass)

# Check rest-server logs — should see X-DevicePass-Verified-* headers
docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-example-rest-server/lxc/console.log
# Expected: Request log entries showing identity headers injected by pv-devicepass

# Proxy to nonexistent service
docker exec pva-test pventer -c pv-devicepass-container \
    curl -s -o /dev/null -w '%{http_code}' --unix-socket /run/pv-devicepass/api.sock http://localhost/services/nonexistent/
# Expected: 404
```

### Expected Results

| Check | Expected |
|-------|----------|
| Both containers | RUNNING |
| GET /skills | Shows network-manager REST service |
| Proxy /services/network-manager/ | Response from rest-server |
| Identity headers | X-DevicePass-Verified-Device present in provider logs |
| Nonexistent service proxy | 404 |

---

## Test 8: DevicePass Hub — Device-to-Hub TCP Tunnel

**Purpose**: Verify the pv-devicepass tunnel client connects to the hub over TCP/IP (IPAM network), the hub polls the device via WebSocket, and the hub REST API exposes device data and routes requests.

### Setup

Build all components (pantavisor must be rebuilt for TCP tunnel support):

```bash
./kas-container shell .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    -c "bitbake pantavisor -c install -f && bitbake pv-devicepass-container pv-devicepass-hub pv-example-device-config-proxy"

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-devicepass-container.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-devicepass-hub.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-device-config-proxy.pvrexport.tgz pvtx.d/
```

> **Note**: `pv-example-device-config-proxy` provides device.json with IPAM pool "internal" on 10.0.3.0/24. The hub uses static IP 10.0.3.10, device gets a dynamic IPAM IP.

### Execute

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 25
```

### Verify

```bash
# Check both containers running
docker exec pva-test lxc-ls -f
# Expected: pv-devicepass-container RUNNING, pv-devicepass-hub RUNNING

# Check hub logs — should show "hub ready" and "listening on 0.0.0.0:8080"
docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-devicepass-hub/lxc/console.log
# Expected:
#   "hub: starting DevicePass Hub"
#   "hub: listening on 0.0.0.0:8080"
#   "hub: hub ready"
#   "hub: [device 0] WebSocket connected"
#   "hub: [device 0] poll /containers -> 200 ..."

# Check device logs — should show TCP tunnel connected
docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-devicepass-container/lxc/console.log
# Expected: "tunnel: connecting to tcp:10.0.3.10:8080"
# Expected: "tunnel: WebSocket connected to 10.0.3.10:8080"

# Wait for hub to poll device
sleep 20

# --- Hub REST API tests ---

# Health check
docker exec pva-test wget -qO- http://10.0.3.10:8080/v1/health 2>/dev/null
# Expected: {"status":"ok","devices_online":1,...}

# List devices
docker exec pva-test wget -qO- http://10.0.3.10:8080/v1/devices 2>/dev/null
# Expected: {"devices":[{"id":"0","online":true,"containers":[...],...}]}

# Get single device
docker exec pva-test wget -qO- http://10.0.3.10:8080/v1/devices/0 2>/dev/null
# Expected: {"id":"0","online":true,"containers":[...],"skills":[...],...}

# Route a request to device via tunnel (call /containers on device)
docker exec pva-test wget -qO- --post-data='{"method":"GET","path":"/containers"}' \
    http://10.0.3.10:8080/v1/devices/0/call 2>/dev/null
# Expected: {"device_id":"0","response":{"id":"hub-0-...","status":200,"body":[...]}}

# Route a request to device (call /daemons)
docker exec pva-test wget -qO- --post-data='{"method":"GET","path":"/daemons"}' \
    http://10.0.3.10:8080/v1/devices/0/call 2>/dev/null
# Expected: {"device_id":"0","response":{"id":"...","status":200,"body":[...]}}

# Group call to all devices
docker exec pva-test wget -qO- --post-data='{"devices":["all"],"method":"GET","path":"/containers"}' \
    http://10.0.3.10:8080/v1/devices/group/call 2>/dev/null
# Expected: {"results":{"0":{"response":{...}}}}

# 404 for nonexistent device
docker exec pva-test wget -qO- http://10.0.3.10:8080/v1/devices/99 2>/dev/null
# Expected: {"error":"device 99 not found"} (wget exits non-zero)

# Device HTTP API still works alongside tunnel
docker exec pva-test pventer -c pv-devicepass-container \
    wget -qO- http://localhost/containers 2>/dev/null
# (or via Unix socket if curl available)
```

### Expected Results

| Check | Expected |
|-------|----------|
| Both containers | RUNNING |
| Hub log | Shows "hub ready", device connected, poll results |
| Device log | Shows "tunnel: connecting to tcp:10.0.3.10:8080", "WebSocket connected" |
| GET /v1/health | `{"status":"ok","devices_online":1,...}` |
| GET /v1/devices | Array with 1 device, online=true, containers populated |
| POST /v1/devices/0/call | Routes to device, returns response with status 200 |
| POST /v1/devices/group/call | Fan-out returns aggregated results |
| Device HTTP API | Still functional alongside tunnel |

---

## Test 9: Container Lifecycle via pv-devicepass

**Purpose**: Verify pv-devicepass can stop and start containers via PUT /containers/{name} (proxied to pv-ctrl).

### Setup

```bash
# Reuse setup from Test 7 (pv-devicepass + rest-server)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-devicepass-container \
    --target pv-example-rest-server

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-devicepass-container.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-rest-server.pvrexport.tgz pvtx.d/
```

### Execute

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Verify

```bash
# Confirm rest-server is running
docker exec pva-test lxc-ls -f
# Expected: pv-example-rest-server RUNNING

# Stop the rest-server via pv-devicepass API
docker exec pva-test pventer -c pv-devicepass-container \
    curl -s -X PUT -d '{"action":"stop"}' \
    --unix-socket /run/pv-devicepass/api.sock http://localhost/containers/pv-example-rest-server | jq .
# Expected: Success response

# Verify it stopped
sleep 3
docker exec pva-test lxc-ls -f
# Expected: pv-example-rest-server STOPPED

# Start it again
docker exec pva-test pventer -c pv-devicepass-container \
    curl -s -X PUT -d '{"action":"start"}' \
    --unix-socket /run/pv-devicepass/api.sock http://localhost/containers/pv-example-rest-server | jq .
# Expected: Success response

# Verify it restarted
sleep 5
docker exec pva-test lxc-ls -f
# Expected: pv-example-rest-server RUNNING
```

### Expected Results

| Check | Expected |
|-------|----------|
| PUT stop | Container transitions to STOPPED |
| PUT start | Container transitions back to RUNNING |
| pv-devicepass stays running | pv-devicepass-container unaffected by target lifecycle |

---

## Quick Reference

### Check Logs
```bash
# pv-devicepass device
docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-devicepass-container/lxc/console.log

# devicepass hub
docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-devicepass-hub/lxc/console.log
```

### Query pv-devicepass Device API
```bash
docker exec pva-test pventer -c pv-devicepass-container \
    curl -s --unix-socket /run/pv-devicepass/api.sock http://localhost/<endpoint> | jq .
```

### Query DevicePass Hub API (TCP)
```bash
docker exec pva-test wget -qO- http://10.0.3.10:8080/v1/health
docker exec pva-test wget -qO- http://10.0.3.10:8080/v1/devices
docker exec pva-test wget -qO- --post-data='{"method":"GET","path":"/containers"}' \
    http://10.0.3.10:8080/v1/devices/0/call
```

### Run Contract Tests
```bash
cd build/workspace/sources/pantavisor/pv-devicepass/contracts
forge test -vv
```

### Deploy to Anvil
```bash
anvil --chain-id 31337 --port 8546 --silent &

cd build/workspace/sources/pantavisor/pv-devicepass/contracts
forge script script/Deploy.s.sol \
    --rpc-url http://localhost:8546 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast
```

### Claim Device on Anvil (via Forge script)
```bash
DEVICE_KEY="0x$(docker exec pva-test pventer -c pv-devicepass-container \
    cat /var/lib/devicepass/device.key 2>/dev/null | grep -v '^export')" \
REGISTRY="0x5FbDB2315678afecb367f032d93F642f64180aa3" \
forge script script/Claim.s.sol \
    --rpc-url http://localhost:8546 \
    --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
    --broadcast
```

### Claim Device on Anvil (via Guardian CLI)
```bash
SCRIPTS=build/workspace/sources/pantavisor/pv-devicepass/scripts
CONTRACT="0x5FbDB2315678afecb367f032d93F642f64180aa3"

# Device generates claim blob
docker exec pva-test pventer -c pv-devicepass-container \
    env DEVICEPASS_CHAIN_ID=31337 DEVICEPASS_CONTRACT=$CONTRACT \
    devicepass-cli onboard --quiet 2>/dev/null | grep '^{' > /tmp/claim.json

# Guardian claims on-chain
$SCRIPTS/devicepass-cli guardian claim \
    --rpc=http://localhost:8546 --contract=$CONTRACT \
    --private-key=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
    /tmp/claim.json
```

### Guardian CLI Quick Commands
```bash
SCRIPTS=build/workspace/sources/pantavisor/pv-devicepass/scripts
FLAGS="--rpc=http://localhost:8546 --contract=0x5FbDB2315678afecb367f032d93F642f64180aa3 --private-key=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

$SCRIPTS/devicepass-cli guardian list $FLAGS
$SCRIPTS/devicepass-cli guardian list $FLAGS --json
$SCRIPTS/devicepass-cli guardian status $FLAGS <DEVICE_ADDR>
$SCRIPTS/devicepass-cli guardian balance --rpc=http://localhost:8546 --private-key=... <DEVICE_ADDR>
$SCRIPTS/devicepass-cli guardian fund --rpc=http://localhost:8546 --private-key=... <DEVICE_ADDR> 0.1
$SCRIPTS/devicepass-cli guardian transfer $FLAGS <DEVICE_ADDR> <NEW_GUARDIAN_ADDR>
$SCRIPTS/devicepass-cli guardian revoke $FLAGS <DEVICE_ADDR>
```

### Fresh Restart
```bash
docker rm -f pva-test; docker volume rm storage-test
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `forge: command not found` | Foundry not installed | Run `curl -L https://foundry.paradigm.xyz \| bash && ~/.foundry/bin/foundryup` |
| `Error: Address already in use` on anvil | Another process on that port | Use `netstat -apn \| grep <port>` to find it; use `--port 8546` |
| `duplicate field 'data'` on `cast call` | cast/anvil version mismatch | Ensure both come from the same `foundryup` install; restart anvil with `~/.foundry/bin/anvil` |
| Deploy address differs from docs | Anvil not freshly started | Restart anvil (state resets); first deploy from account #0 is always deterministic |
| Claim fails with `InvalidSignature` | chain_id mismatch | Device onboard uses `DEVICEPASS_CHAIN_ID` (default 8453); Claim.s.sol uses `block.chainid` from Anvil (31337). The Forge script generates its own signature, so this only matters for manual `cast` claims |
| `head: invalid option -- 'c'` in devicepass-cli | Busybox head doesn't support -c | Fixed — scripts use shell parameter expansion instead |
| pv-devicepass-container not starting | Missing /proc bind mount | Check lxc-extra.conf has `/proc` entry |
| "tunnel: connect failed" in pv-devicepass log | Hub not running or IPAM not set up | Check hub logs, verify IPAM pool is deployed (device-config-proxy), check `ip addr` in containers for IPAM IPs |
| GET /skills returns empty array | xconnect-graph polling hasn't found REST services | Wait 10s for graph poll cycle, check xconnect-graph directly |
| Proxy returns 502 Bad Gateway | Provider container not running or socket path wrong | Check provider status with `lxc-ls -f`, verify services.json socket path |
| PUT /containers returns error | Container has restart_policy=system | Only containers with restart_policy=container can be stopped via API |

---

## Test 10: Guardian CLI — Claim from Device Blob

**Purpose**: End-to-end flow: device generates identity and claim blob in the appengine container, guardian claims it on-chain from the host using `devicepass-cli guardian claim`.

### Prerequisites

- Appengine running with pv-devicepass-container (see Common Appengine Setup)
- Anvil running on port 8546 with contract deployed (see Test 5)
- Device identity initialized (see Test 2)

### Execute

```bash
SCRIPTS=build/workspace/sources/pantavisor/pv-devicepass/scripts
CONTRACT="0x5FbDB2315678afecb367f032d93F642f64180aa3"  # or your deploy address
GUARDIAN_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

# Step 1: Device generates claim blob (inside container)
docker exec pva-test pventer -c pv-devicepass-container \
    env DEVICEPASS_CHAIN_ID=31337 DEVICEPASS_CONTRACT=$CONTRACT \
    devicepass-cli onboard --quiet 2>/dev/null | grep '^{' > /tmp/device-claim.json

cat /tmp/device-claim.json | jq .
# Expected: {"version":1,"device":"0x...","nonce":...,"chain_id":31337,...,"signature":"0x..."}

# Step 2: Guardian claims on-chain (from host)
$SCRIPTS/devicepass-cli guardian claim \
    --rpc=http://localhost:8546 \
    --contract=$CONTRACT \
    --private-key=$GUARDIAN_KEY \
    /tmp/device-claim.json
# Expected: "Device claimed successfully"
```

### Verify

```bash
DEVICE=$(jq -r '.device' /tmp/device-claim.json)

$SCRIPTS/devicepass-cli guardian status \
    --rpc=http://localhost:8546 \
    --contract=$CONTRACT \
    --private-key=$GUARDIAN_KEY \
    $DEVICE
# Expected: Device Passport with Active: true, Guardian matching Anvil account #1
```

### Expected Results

| Check | Expected |
|-------|----------|
| Device onboard blob | Valid JSON with device, nonce, chain_id, signature |
| Guardian claim TX | Success, PassportCreated event |
| Passport query | device, guardian, createdAt, active=true |

---

## Test 11: Guardian CLI — List, Status, Balance, Fund

**Purpose**: Verify guardian management commands against an Anvil testnet with a claimed device.

### Prerequisites

- Device claimed on Anvil (complete Test 10 first)

### Execute

```bash
SCRIPTS=build/workspace/sources/pantavisor/pv-devicepass/scripts
CONTRACT="0x5FbDB2315678afecb367f032d93F642f64180aa3"
GUARDIAN_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
DEVICE=$(jq -r '.device' /tmp/device-claim.json)

# List devices
$SCRIPTS/devicepass-cli guardian list \
    --rpc=http://localhost:8546 --contract=$CONTRACT --private-key=$GUARDIAN_KEY
# Expected: Table with 1 device, Active=true

# List devices (JSON)
$SCRIPTS/devicepass-cli guardian list \
    --rpc=http://localhost:8546 --contract=$CONTRACT --private-key=$GUARDIAN_KEY --json 2>/dev/null
# Expected: Valid JSON array

# Status
$SCRIPTS/devicepass-cli guardian status \
    --rpc=http://localhost:8546 --contract=$CONTRACT --private-key=$GUARDIAN_KEY $DEVICE
# Expected: Device Passport with all fields

# Balance (initially 0)
$SCRIPTS/devicepass-cli guardian balance \
    --rpc=http://localhost:8546 --private-key=$GUARDIAN_KEY $DEVICE
# Expected: 0 ETH

# Fund device
$SCRIPTS/devicepass-cli guardian fund \
    --rpc=http://localhost:8546 --private-key=$GUARDIAN_KEY $DEVICE 0.1
# Expected: "Funded successfully", balance updated

# Balance after fund
$SCRIPTS/devicepass-cli guardian balance \
    --rpc=http://localhost:8546 --private-key=$GUARDIAN_KEY $DEVICE
# Expected: 0.1 ETH
```

### Expected Results

| Command | Expected |
|---------|----------|
| `guardian list` | Shows 1 device, Active=true |
| `guardian list --json` | Valid JSON array |
| `guardian status` | Device, Guardian, Created, Active, Balance |
| `guardian balance` | 0 ETH initially |
| `guardian fund 0.1` | TX success, balance updated |
| `guardian balance` (after) | 0.1 ETH |

---

## Test 12: Guardian CLI — Transfer and Revoke

**Purpose**: Verify guardian ownership transfer and device passport revocation.

### Prerequisites

- Device claimed on Anvil (complete Test 10 first)

### Execute

```bash
SCRIPTS=build/workspace/sources/pantavisor/pv-devicepass/scripts
CONTRACT="0x5FbDB2315678afecb367f032d93F642f64180aa3"
GUARDIAN_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
NEW_GUARDIAN_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
NEW_GUARDIAN=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
DEVICE=$(jq -r '.device' /tmp/device-claim.json)

# Transfer to new guardian
$SCRIPTS/devicepass-cli guardian transfer \
    --rpc=http://localhost:8546 --contract=$CONTRACT --private-key=$GUARDIAN_KEY \
    $DEVICE $NEW_GUARDIAN
# Expected: "Device transferred"

# Verify old guardian has no devices
$SCRIPTS/devicepass-cli guardian list \
    --rpc=http://localhost:8546 --contract=$CONTRACT --private-key=$GUARDIAN_KEY
# Expected: "No devices found"

# Verify new guardian has the device
$SCRIPTS/devicepass-cli guardian list \
    --rpc=http://localhost:8546 --contract=$CONTRACT --private-key=$NEW_GUARDIAN_KEY
# Expected: 1 device

# Revoke (as new guardian)
$SCRIPTS/devicepass-cli guardian revoke \
    --rpc=http://localhost:8546 --contract=$CONTRACT --private-key=$NEW_GUARDIAN_KEY \
    $DEVICE
# Expected: "Device passport revoked"

# Verify revoked
$SCRIPTS/devicepass-cli guardian status \
    --rpc=http://localhost:8546 --contract=$CONTRACT --private-key=$NEW_GUARDIAN_KEY \
    $DEVICE
# Expected: Active: false
```

### Expected Results

| Step | Expected |
|------|----------|
| Transfer | Old guardian loses device, new guardian gains it |
| Old guardian list | Empty |
| New guardian list | 1 device |
| Revoke | Active becomes false |
| Status after revoke | active=false |

---

## Test 13: Guardian CLI — Pipe Workflow

**Purpose**: Verify the pipe workflow where device onboard output goes directly to guardian claim via stdin.

### Execute

```bash
SCRIPTS=build/workspace/sources/pantavisor/pv-devicepass/scripts
CONTRACT="0x5FbDB2315678afecb367f032d93F642f64180aa3"
GUARDIAN_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

# Re-init device identity (previous was revoked)
docker exec pva-test pventer -c pv-devicepass-container devicepass-cli init --force

# Pipe: device onboard → guardian claim
docker exec pva-test pventer -c pv-devicepass-container \
    env DEVICEPASS_CHAIN_ID=31337 DEVICEPASS_CONTRACT=$CONTRACT \
    devicepass-cli onboard --quiet 2>/dev/null | grep '^{' | \
    $SCRIPTS/devicepass-cli guardian claim \
        --rpc=http://localhost:8546 --contract=$CONTRACT --private-key=$GUARDIAN_KEY
# Expected: "Device claimed successfully"
```

### Expected Results

| Check | Expected |
|-------|----------|
| Pipe claim | TX success without intermediate file |

---

## Future: Testnet Deployment (Base Sepolia)

When ready to move beyond Anvil:

```bash
# Base Sepolia RPC
RPC="https://sepolia.base.org"

# Deploy (needs real ETH on Base Sepolia)
forge script script/Deploy.s.sol \
    --rpc-url "$RPC" \
    --private-key <YOUR_DEPLOYER_KEY> \
    --broadcast \
    --verify

# Claim (guardian needs Base Sepolia ETH)
DEVICE_KEY="0x..." \
REGISTRY="<deployed_address>" \
forge script script/Claim.s.sol \
    --rpc-url "$RPC" \
    --private-key <YOUR_GUARDIAN_KEY> \
    --broadcast

# Device needs DEVICEPASS_CHAIN_ID=84532 (Base Sepolia chain ID)
# and DEVICEPASS_CONTRACT=<deployed_address>
```

Get Base Sepolia ETH from faucets:
- https://www.alchemy.com/faucets/base-sepolia
- https://faucet.quicknode.com/base/sepolia
