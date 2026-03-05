# DevicePass

DevicePass gives any machine — IoT device, server, VM, container, CI runner — a blockchain-native identity. The machine generates an Ethereum-compatible secp256k1 keypair, signs a claim blob, and a guardian submits it to the DevicePassRegistry smart contract to establish ownership. No tokens to seed, no secrets to distribute, no central authority.

## How It Works

```
Machine                        Guardian                                  Chain
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

- **Identity is local.** Key generation and claim blob creation happen entirely on the machine. No hub, no network, no chain access required. The claim blob is a portable cryptographic proof that can be transferred via any channel.
- **The smart contract is the sole ownership authority.** Guardian-machine relationships are recorded on-chain. Any application can verify ownership by querying the contract — no central server needed.
- **The hub is just an app.** It reads the chain to authenticate machines and route traffic. It has no role in claiming, ownership, or identity. If the hub goes down, ownership state is intact on-chain.
- **Universal.** The same identity model works for embedded devices, cloud VMs, Kubernetes pods, bare-metal servers — anything that can hold a private key.
- **Supply chain friendly.** A factory can generate identities, create claim blobs, register itself as initial guardian, and later transfer ownership on-chain — equivalent to FIDO FDO ownership vouchers but backed by a distributed ledger.

## Quick Start

DevicePass runs anywhere. The `devicepass-cli` needs only two C binaries (`keccak256sum`, `ethsign`) for device-side commands, and Foundry (`cast`) for guardian-side commands.

### 1. Device: Generate Identity and Claim Blob

On the machine that needs an identity:

```bash
# Generate a secp256k1 keypair and derive an Ethereum address
devicepass-cli dev init

# Create a signed claim blob (JSON to stdout)
devicepass-cli dev onboard --quiet > claim.json
```

That's it — the machine now has an identity. The claim blob is a signed proof that can be transferred to a guardian via any channel (copy-paste, file, QR code, API call). It contains no secrets.

### 2. Guardian: Deploy Contract and Claim

On any machine with [Foundry](https://book.getfoundry.sh/) installed:

```bash
# Start a local testnet (for development)
anvil --chain-id 31337 --port 8546 --silent &

# Deploy the registry contract
devicepass-cli guardian deploy \
    --rpc=http://localhost:8546 \
    --private-key=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Claim the device
devicepass-cli guardian claim claim.json \
    --rpc=http://localhost:8546 \
    --contract=0x5FbDB2315678afecb367f032d93F642f64180aa3 \
    --private-key=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

The machine is now on-chain with a guardian. Any service can verify ownership by querying `passports(address)` on the contract.

### 3. Manage

```bash
FLAGS="--rpc=http://localhost:8546 --contract=0x5FbDB... --private-key=0x5996..."

devicepass-cli guardian list $FLAGS              # List all your devices
devicepass-cli guardian status 0xDEV... $FLAGS   # Passport details
devicepass-cli guardian fund 0xDEV... 0.01 $FLAGS  # Send ETH
devicepass-cli guardian transfer 0xDEV... 0xNEW... $FLAGS  # Transfer ownership
devicepass-cli guardian revoke 0xDEV... $FLAGS   # Deactivate
```

## Try It with Pantavisor Appengine

For a complete emulated device environment with hub and IPAM networking, use the pre-built appengine image. This bundles everything — device container, hub, and network config — into a single Docker image.

### Build

```bash
git clone -b poc/devicepass https://github.com/pantavisor/meta-pantavisor
cd meta-pantavisor

./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pantavisor-image-devicepass
```

### Run

```bash
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-image-devicepass-docker.tar

docker run --name pva-dp -d --privileged \
    -v storage-dp:/var/pantavisor/storage \
    pantavisor-image-devicepass:1.0
```

Wait ~20 seconds, then verify:

```bash
docker exec pva-dp lxc-ls -f
# pv-devicepass-container  RUNNING  10.0.3.2
# pv-devicepass-hub        RUNNING  10.0.3.10
```

No pvtx.d volume mount needed — containers are baked into the image and auto-provision on first boot.

### Use

```bash
# Generate identity inside the emulated device
docker exec pva-dp pventer -c pv-devicepass-container "devicepass-cli dev init"
docker exec pva-dp pventer -c pv-devicepass-container "devicepass-cli dev status"

# Create claim blob
docker exec pva-dp pventer -c pv-devicepass-container \
    "env DEVICEPASS_CHAIN_ID=31337 devicepass-cli dev onboard --quiet"
```

From here, use the guardian CLI on the host to deploy a contract (Anvil) and claim the device. The [E2E test script](build/workspace/sources/pantavisor/pv-devicepass/scripts/test-e2e-guardian-bound.sh) automates the full flow.

### Teardown

```bash
docker rm -f pva-dp
docker volume rm storage-dp
```

## CLI Reference

```bash
devicepass-cli --version          # Show version
devicepass-cli dev <subcommand>   # Device-side commands (identity, onboarding)
devicepass-cli guardian <subcommand>  # Guardian/fleet management commands
```

Top-level shortcuts are available for device commands (`devicepass-cli init` is equivalent to `devicepass-cli dev init`) for backwards compatibility.

## Device Side

All device commands are fully offline — no network or chain access required.

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

Signs a claim blob that proves identity. Output is JSON:

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

The guardian runs `devicepass-cli guardian` commands on any machine with [Foundry](https://book.getfoundry.sh/) (`cast`, `forge`) installed.

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

The guardian submits the machine's signed claim blob to the contract. On success, the guardian becomes the machine's owner.

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

Add `--json` for machine-readable output.

### Device Status

```bash
devicepass-cli guardian status 0x71e9fc79... --rpc=... --contract=... --private-key=...
```

### Check Balance / Fund / Transfer / Revoke

```bash
devicepass-cli guardian balance 0xDEV... --rpc=... --private-key=...
devicepass-cli guardian fund 0xDEV... 0.1 --rpc=... --private-key=...
devicepass-cli guardian transfer 0xDEV... 0xNEW... --rpc=... --contract=... --private-key=...
devicepass-cli guardian revoke 0xDEV... --rpc=... --contract=... --private-key=...
```

## Smart Contract

The `DevicePassRegistry` contract is a Solidity contract deployed on any EVM chain.

### Functions

| Function | Description |
|----------|-------------|
| `claimDevice(address, address, uint256, bytes)` | Guardian claims a machine (device, guardian-in-blob, nonce, sig) |
| `transferDevice(address, address)` | Transfer ownership to new guardian |
| `revokeDevice(address)` | Deactivate passport |
| `passports(address)` | Query passport: device, guardian, createdAt, active |
| `guardianDeviceCount(address)` | Number of devices owned by guardian |
| `guardianDeviceAt(address, uint256)` | Device address at index in guardian's list |

### Events

| Event | Description |
|-------|-------------|
| `PassportCreated(device, guardian)` | New machine claimed |
| `PassportTransferred(device, oldGuardian, newGuardian)` | Ownership changed |
| `PassportRevoked(device, guardian)` | Machine deactivated |

### Signature Scheme

The machine signs: `keccak256("\x19Ethereum Signed Message:\n32" + keccak256(abi.encodePacked(device, guardian, nonce, chainId)))`.

For open claims, `guardian` is `0x0000000000000000000000000000000000000000`. For guardian-bound claims, it's the target guardian's address. The contract enforces that if guardian is non-zero, only that address can submit the claim.

Standard EIP-191 personal sign, compatible with MetaMask, ethers.js, and any Ethereum wallet.

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

## Serve Mode

After claiming, the machine can run `devicepass-cli dev serve` as its persistent runtime. This connects to the hub, learns about its guardian, opens a tunnel, and announces container specs.

```bash
devicepass-cli dev serve
```

### Startup Flow

```
1. Load identity from /var/lib/devicepass/
2. Connect WebSocket to hub
3. Hub sends auth challenge → machine signs with device key
4. Hub verifies signature, checks chain for passport
   ├── Passport exists → hub responds with guardian address
   │   → enter main loop (heartbeat, tunnel, specs)
   │
   └── No passport (not yet claimed) → hub rejects
       → wait with exponential backoff, retry
       → once guardian claims on-chain, next retry succeeds
```

## Architecture

### Components

| Component | Language | Location | Purpose |
|-----------|----------|----------|---------|
| `keccak256sum` | C | `pv-devicepass/keccak256sum.c` | Ethereum Keccak-256 hash (not NIST SHA-3) |
| `ethsign` | C | `pv-devicepass/ethsign.c` | secp256k1 key generation and ECDSA signing |
| `devicepass-cli` | Shell | `pv-devicepass/scripts/` | CLI dispatcher for device and guardian commands |
| `DevicePassRegistry` | Solidity | `pv-devicepass/contracts/src/` | On-chain passport registry |
| `pv-devicepass` | C | `pv-devicepass/pv-devicepass.c` | HTTP API daemon (serve mode) |

### Configuration

Environment variables:

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
# 2. On machine — generate identity and claim blob
devicepass-cli dev init
devicepass-cli dev onboard --quiet > claim.json
# 3. Transfer claim.json to guardian
# 4. Guardian claims
devicepass-cli guardian claim claim.json --rpc=... --contract=... --private-key=...
# 5. Machine authenticates via chain — done
```

### Factory / Supply Chain

```bash
# 1. Factory provisions device
devicepass-cli dev init
devicepass-cli dev onboard --quiet --guardian=0xFACTORY... > claim.json
# 2. Factory claims as initial guardian
devicepass-cli guardian claim claim.json --rpc=... --contract=... --private-key=0xFACTORY_KEY...
# 3. Ship device, transfer on-chain to customer
devicepass-cli guardian transfer 0xDEVICE... 0xCUSTOMER... --rpc=... --contract=... --private-key=...
```

## See Also

- [TESTPLANS-DEVICEPASS.md](TESTPLANS-DEVICEPASS.md) — Executable test plans and E2E test script
