# DevicePass

DevicePass gives IoT devices blockchain-native identity and lets guardians manage them on-chain. Each device generates an Ethereum-compatible secp256k1 keypair, signs a claim blob, and a guardian submits it to the DevicePassRegistry smart contract to establish ownership.

## How It Works

```
Device                         Guardian                                  Chain
  |                               |                                        |
  |  devicepass-cli dev init      |    CLAIMING IS LOCAL + OFFLINE         |
  |  (generate keypair)          |    No hub involved                    |
  |                               |                                        |
  |  devicepass-cli dev onboard  |                                        |
  |  (sign claim blob)    ------>|                                        |
  |              QR/USB/file/...  |                                        |
  |                               |  guardian claim <blob>                 |
  |                               |  (submit to contract)   ------------->|
  |                               |                                        | claimDevice()
  |                               |                                        | verify sig
  |                               |                                        | create passport
  |                               |<---------  PassportCreated event      |
  |                               |                                        |
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
                                                               Hub
  |  pv-devicepass daemon         |                             |          |
  |  (connect to hub)      ---------------------------------------->     |
  |                               |                             | check   |
  |                               |                             | chain-->|
  |  <-- guardian: 0x7a3f...  -----------------------------------------  |
  |  (now knows its guardian)     |                             |          |
  |  tunnel open            <------------------------------------------>  |
  |                               |                             |          |
  |                               |  REST API via hub  -------->|          |
  |                               |  (hub verifies guardian) -->|--------->|
```

## Design Principles

- **Claiming is local and offline.** Identity generation and claim blob creation happen entirely on the device. No hub, no network, no chain access required. The claim blob is a portable cryptographic proof that can be transferred via any channel.
- **The smart contract is the sole ownership authority.** Guardian-device relationships are recorded on-chain. Any application can verify ownership by querying the contract — no central server needed.
- **The hub is just an app.** It reads the chain to authenticate devices and route traffic. It has no role in claiming, ownership, or identity. If the hub goes down, ownership state is intact on-chain and any replacement hub can pick up where it left off.
- **Supply chain friendly.** A factory can generate device identities, create claim blobs, register itself as initial guardian, and later transfer ownership on-chain — equivalent to FIDO FDO ownership vouchers but backed by a distributed ledger instead of a centralized rendezvous server.

## Quick Start — Try DevicePass in Appengine

The fastest way to try DevicePass is the pre-built appengine image. It bundles the device container, hub, and IPAM networking — no manual setup needed.

### 1. Build the Image

```bash
git clone -b poc/devicepass https://github.com/pantavisor/meta-pantavisor
cd meta-pantavisor

./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pantavisor-image-devicepass
```

### 2. Run It

```bash
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-image-devicepass-docker.tar

docker run --name pva-dp -d --privileged \
    -v storage-dp:/var/pantavisor/storage \
    pantavisor-image-devicepass:1.0
```

Wait ~20 seconds for containers to start, then verify:

```bash
docker exec pva-dp lxc-ls -f
# pv-devicepass-container  RUNNING  10.0.3.2
# pv-devicepass-hub        RUNNING  10.0.3.10
```

No pvtx.d volume mount needed — containers are baked into the image and auto-provision on first boot.

### 3. Generate Device Identity and Claim

```bash
# Generate identity inside the device container
docker exec pva-dp pventer -c pv-devicepass-container "devicepass-cli dev init"

# Check status
docker exec pva-dp pventer -c pv-devicepass-container "devicepass-cli dev status"
```

From here, follow the [guardian CLI workflow](#guardian-side) to deploy a contract on Anvil and claim the device. The [E2E test script](build/workspace/sources/pantavisor/pv-devicepass/scripts/test-e2e-guardian-bound.sh) automates the full flow.

### 4. Teardown

```bash
docker rm -f pva-dp
docker volume rm storage-dp
```

## CLI Overview

```bash
devicepass-cli --version          # Show version
devicepass-cli dev <subcommand>   # Device-side commands (identity, onboarding)
devicepass-cli guardian <subcommand>  # Guardian/fleet management commands
```

Top-level shortcuts are available for device commands (`devicepass-cli init` is equivalent to `devicepass-cli dev init`) for backwards compatibility.

## Device Side

The device runs `devicepass-cli` inside a Pantavisor container (`pv-devicepass-container`). All device commands are fully offline — no network or chain access required.

### Generate Identity

```bash
devicepass-cli dev init
```

Creates a secp256k1 keypair and derives an Ethereum address:

```
Generating device identity...
  Address:   0x71e9fc79c8a7854a6f24aed8cb25bd8d6984e719
  ID:        dp-71e9fc79c8a7
  Key dir:   /var/lib/devicepass
```

Files created in `/var/lib/devicepass/`:

| File | Description |
|------|-------------|
| `device.key` | Private key (hex, chmod 600) |
| `device.pub.hex` | Public key (uncompressed, no 04 prefix) |
| `device.address` | Ethereum address (0x-prefixed) |
| `device.id` | Short ID (`dp-` + first 12 hex chars) |

### Create Claim Blob

```bash
# Open claim — any guardian can submit
devicepass-cli dev onboard --quiet

# Guardian-bound claim — only the specified guardian can submit
devicepass-cli dev onboard --quiet --guardian=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
```

Signs a claim blob that proves device identity. Output is JSON:

```json
{
  "version": 2,
  "device": "0x71e9fc79c8a7854a6f24aed8cb25bd8d6984e719",
  "guardian": "0x0000000000000000000000000000000000000000",
  "nonce": 1771181642,
  "chain_id": 31337,
  "contract": "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
  "signature": "0xefc54fe9d2c2ec857b5564..."
}
```

Two claim modes:

| Mode | Flag | Signed over | Who can submit |
|------|------|-------------|----------------|
| Open | (default) | `(device, 0x0, nonce, chainId)` | Any guardian |
| Guardian-bound | `--guardian=0x...` | `(device, guardian, nonce, chainId)` | Only that guardian |

**Open claims** are simpler — suitable when the blob transfer channel is trusted (serial console, USB, factory floor). **Guardian-bound claims** are for untrusted channels or supply chain scenarios where the blob might be intercepted.

Transfer the blob to the guardian via any channel (copy-paste, QR code, file transfer). The blob contains no secrets; it's a signed proof of identity.

Options:
- `--quiet` — JSON-only output (no log messages)
- `--guardian=0x...` — bind claim to a specific guardian address
- `--out=FILE` — write to file instead of stdout
- `DEVICEPASS_CHAIN_ID=N` — override chain ID (default: 8453 for Base)
- `DEVICEPASS_CONTRACT=0x...` — override contract address

### Check Status

```bash
devicepass-cli dev status
```

Shows local identity info: address, ID, chain ID, contract, key directory.

### Export Key

```bash
devicepass-cli dev export-key                # hex output
devicepass-cli dev export-key --format=bin   # binary output
```

## Guardian Side

The guardian runs `devicepass-cli guardian` commands on a machine with [Foundry](https://book.getfoundry.sh/) (`cast`) installed. These commands interact with the on-chain DevicePassRegistry contract.

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
~/.foundry/bin/foundryup

# Add to PATH
export PATH="$HOME/.foundry/bin:$PATH"
```

### Common Flags

All guardian commands accept:

| Flag | Env Variable | Description |
|------|-------------|-------------|
| `--rpc=URL` | `DEVICEPASS_RPC` | RPC endpoint (default: http://localhost:8545) |
| `--contract=ADDR` | `DEVICEPASS_CONTRACT` | Registry contract address |
| `--private-key=KEY` | `DEVICEPASS_PRIVATE_KEY` | Guardian private key |
| `--account=NAME` | `DEVICEPASS_ACCOUNT` | Cast keystore account name |

### Deploy Contract

```bash
devicepass-cli guardian deploy \
    --rpc=http://localhost:8546 \
    --private-key=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

Deploys the DevicePassRegistry contract using `forge`. Requires Foundry and contract sources (auto-detected relative to the CLI or via `DEVICEPASS_CONTRACTS_DIR`).

### Claim a Device

```bash
# From a file
devicepass-cli guardian claim /path/to/claim.json \
    --rpc=http://localhost:8546 \
    --contract=0xe7f172... \
    --private-key=0x5996...

# Piped from device onboard output
devicepass-cli dev onboard --quiet | devicepass-cli guardian claim --rpc=... --contract=... --private-key=...
```

The guardian submits the device's signed claim blob to the contract. On success, the guardian becomes the device's owner.

### List Devices

```bash
devicepass-cli guardian list --rpc=... --contract=... --private-key=...
```

```
Guardian: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
Devices:  2

#     Device                                        Active    Created
---   --------------------------------------------  --------  ----------
0     0x71e9fc79C8A7854a6f24aed8cb25bd8D6984E719    true      1771181772
1     0x8b2a1c5ef903D0b772E8f44c9aF90021c5e30a12    true      1771182100
```

Add `--json` for machine-readable output:

```json
[
  {"device": "0x71e9...", "guardian": "0x7099...", "createdAt": 1771181772, "active": true},
  {"device": "0x8b2a...", "guardian": "0x7099...", "createdAt": 1771182100, "active": true}
]
```

### Device Status

```bash
devicepass-cli guardian status 0x71e9fc79... --rpc=... --contract=... --private-key=...
```

```
Device Passport
  Device:    0x71e9fc79C8A7854a6f24aed8cb25bd8D6984E719
  Guardian:  0x70997970C51812dc3A010C7d01b50e0d17dc79C8
  Created:   1771181772
  Active:    true
  Balance:   100000000000000000
```

### Check Balance

```bash
devicepass-cli guardian balance 0x71e9fc79... --rpc=... --private-key=...
```

```
Device:  0x71e9fc79c8a7854a6f24aed8cb25bd8d6984e719
Balance: 0.100000000000000000 ETH
```

### Fund Device

```bash
devicepass-cli guardian fund 0x71e9fc79... 0.1 --rpc=... --private-key=...
```

Sends ETH from the guardian wallet to the device address.

### Transfer Ownership

```bash
devicepass-cli guardian transfer 0x71e9fc79... 0x3C44CdDd... \
    --rpc=... --contract=... --private-key=...
```

Transfers device ownership to a new guardian. Only the current guardian can transfer.

### Revoke Device

```bash
devicepass-cli guardian revoke 0x71e9fc79... --rpc=... --contract=... --private-key=...
```

Deactivates the device passport. The device record remains on-chain but `active` is set to false.

## Smart Contract

The `DevicePassRegistry` contract is a Solidity contract deployed on an EVM chain.

### Functions

| Function | Description |
|----------|-------------|
| `claimDevice(address, address, uint256, bytes)` | Guardian claims a device (device, guardian-in-blob, nonce, sig) |
| `transferDevice(address, address)` | Transfer ownership to new guardian |
| `revokeDevice(address)` | Deactivate device passport |
| `passports(address)` | Query passport: device, guardian, createdAt, active |
| `guardianDeviceCount(address)` | Number of devices owned by guardian |
| `guardianDeviceAt(address, uint256)` | Device address at index in guardian's list |

### Events

| Event | Description |
|-------|-------------|
| `PassportCreated(device, guardian)` | New device claimed |
| `PassportTransferred(device, oldGuardian, newGuardian)` | Ownership changed |
| `PassportRevoked(device, guardian)` | Device deactivated |

### Signature Scheme

The device signs: `keccak256("\x19Ethereum Signed Message:\n32" + keccak256(abi.encodePacked(device, guardian, nonce, chainId)))`.

For open claims, `guardian` is `0x0000000000000000000000000000000000000000`. For guardian-bound claims, it's the target guardian's address. The contract verifies accordingly — if the recovered guardian is non-zero, only that address can submit the claim.

This is standard EIP-191 personal sign, compatible with MetaMask, ethers.js, and any Ethereum wallet.

### Local Testing with Anvil

```bash
# Start local testnet
anvil --chain-id 31337 --port 8546 --silent &

# Deploy
cd build/workspace/sources/pantavisor/pv-devicepass/contracts
forge script script/Deploy.s.sol \
    --rpc-url http://localhost:8546 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast

# Run unit tests
forge test -vv
```

## Device Serve Mode

After claiming, the device runs `devicepass-cli dev serve` as its persistent runtime. This connects to the hub, learns about its guardian, opens a tunnel, and announces container specs.

```bash
devicepass-cli dev serve
```

### Startup Flow

```
1. Load identity from /var/lib/devicepass/
2. Connect WebSocket to hub (wss://api.devicepass.ai/v1/device/connect)
3. Hub sends auth challenge → device signs with device key
4. Hub verifies signature, checks chain for passport
   ├── Passport exists → hub responds with guardian address
   │   → device saves passport.json
   │   → push metadata + container specs
   │   → enter main loop (heartbeat, tunnel, spec/meta watches)
   │
   └── No passport (not yet claimed) → hub rejects: "not_claimed"
       → device waits with exponential backoff (30s, 60s, 120s, ... cap 5min)
       → retry from step 2
       → once guardian claims on-chain, next retry succeeds
```

The device learns about its guardian only when the hub confirms the passport. Before that, `serve` retries patiently. This means a device can be powered on and start `serve` before a guardian has claimed it — it will connect automatically once claimed.

### Runtime

Once connected, `serve` enters a main loop:
- **Heartbeat** every 30s
- **Spec watch**: monitors `/var/lib/devicepass/specs/` for container OpenAPI changes, pushes updates to hub
- **Metadata watch**: monitors `/var/lib/devicepass/meta.json`, pushes updates to hub
- **Tunnel handler**: receives HTTP-over-WebSocket requests from hub, proxies to local containers
- **Reconnect**: on disconnect, reconnects with exponential backoff

## Architecture

### Components

| Component | Language | Location | Purpose |
|-----------|----------|----------|---------|
| `keccak256sum` | C | `pv-devicepass/keccak256sum.c` | Ethereum Keccak-256 hash (not NIST SHA-3) |
| `ethsign` | C | `pv-devicepass/ethsign.c` | secp256k1 key generation and ECDSA signing |
| `devicepass-cli` | Shell | `pv-devicepass/scripts/` | CLI dispatcher for device and guardian commands |
| `DevicePassRegistry` | Solidity | `pv-devicepass/contracts/src/` | On-chain device passport registry |
| `pv-devicepass` | C | `pv-devicepass/pv-devicepass.c` | HTTP API daemon (serve mode) |

### Device Container

The `pv-devicepass-container` Pantavisor container packages all device-side tools. It runs in the appengine alongside other containers.

```
pv-devicepass-container
├── /usr/bin/devicepass-cli        # CLI dispatcher
├── /usr/bin/keccak256sum          # Keccak-256 hash
├── /usr/bin/ethsign               # secp256k1 ECDSA
├── /usr/bin/pv-devicepass         # HTTP API daemon
├── /usr/lib/devicepass/           # Shell script libraries
│   ├── config.sh
│   ├── display.sh
│   ├── identity.sh
│   ├── signing.sh
│   └── guardian/                  # Guardian subcommands
└── /var/lib/devicepass/           # Runtime identity data
```

### Configuration

Environment variables (set in container or shell):

| Variable | Default | Description |
|----------|---------|-------------|
| `DEVICEPASS_DIR` | `/var/lib/devicepass` | Identity data directory |
| `DEVICEPASS_CHAIN_ID` | `8453` | Target chain ID (8453=Base, 31337=Anvil) |
| `DEVICEPASS_CONTRACT` | `0x000...000` | Registry contract address |
| `DEVICEPASS_RPC` | `http://localhost:8545` | RPC endpoint (guardian side) |

## Typical Workflows

### Single Owner (DIY / Small Fleet)

```bash
# 1. Deploy contract (one-time)
# On Anvil for testing, Base/Sepolia for production

# 2. On device — generate identity and open claim blob
devicepass-cli dev init
devicepass-cli dev onboard --quiet > /tmp/claim.json

# 3. Transfer claim.json to guardian (USB, copy-paste, QR, etc.)

# 4. Guardian claims device
devicepass-cli guardian claim /tmp/claim.json \
    --rpc=https://sepolia.base.org \
    --contract=0x... \
    --private-key=0x...

# 5. Device connects to hub, authenticates via chain — done
```

### Factory / Supply Chain

```bash
# 1. Factory provisions device on assembly line
devicepass-cli dev init
devicepass-cli dev onboard --quiet --guardian=0xFACTORY... > /tmp/claim.json

# 2. Factory claims as initial guardian
devicepass-cli guardian claim /tmp/claim.json \
    --rpc=... --contract=... --private-key=0xFACTORY_KEY...

# 3. Print sticker with device short ID (dp-71e9fc79c8a7)
#    Ship device to customer

# 4. Customer provides their address, factory transfers on-chain
devicepass-cli guardian transfer 0xDEVICE... 0xCUSTOMER... \
    --rpc=... --contract=... --private-key=0xFACTORY_KEY...

# 5. Customer is now guardian — device authenticates with their hub
```

### Manage Fleet

```bash
# See all devices
devicepass-cli guardian list --rpc=... --contract=... --private-key=...

# Check a device
devicepass-cli guardian status 0x... --rpc=... --contract=... --private-key=...

# Fund a device wallet
devicepass-cli guardian fund 0x... 0.01 --rpc=... --private-key=...

# Transfer to another guardian
devicepass-cli guardian transfer 0x... 0xNEW... --rpc=... --contract=... --private-key=...
```

## See Also

- [TESTPLANS-DEVICEPASS.md](TESTPLANS-DEVICEPASS.md) — Executable test plans
- [devicepass-cli-and-hub-plan-v6.md](devicepass-cli-and-hub-plan-v6.md) — Full implementation plan (including hub and AI integration)
