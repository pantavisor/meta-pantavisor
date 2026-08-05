---
title: PVR CLI
description: Essential pvr commands and workflows
---

## Overview

The **pvr** command-line tool is your primary interface for managing Pantavisor repositories and devices. It enables repository management, application deployment, device interaction, and system configuration.

This page covers the essential commands and workflows. For the full command set,
run `pvr help` (or `pvr help <command>`); other day-to-day commands not covered
here include `pvr status`, `pvr diff`, `pvr export`/`pvr import`, and
`pvr login`/`pvr whoami`.

## Installation

### Quick Install (Linux/macOS)

The fastest and easiest way to install the Pantavisor CLI (PVR) is via the official install script. It automatically detects your OS and architecture:

```bash
# Install Pantavisor CLI (PVR)
curl -sL https://gitlab.com/pantacor/pvr/-/raw/master/install.sh | bash
```

### Quick Install (Windows)

For Windows users using PowerShell:

```powershell
Invoke-WebRequest -Uri https://gitlab.com/pantacor/pvr/-/raw/master/install.ps1 -OutFile install.ps1; .\install.ps1
```

### Advanced Install Script Usage

You can customize the installation using environment variables:

```bash
# Install a specific version
PVR_VERSION=046 bash <(curl -sL https://gitlab.com/pantacor/pvr/-/raw/master/install.sh)

# Install from the develop channel (latest unstable features)
PVR_CHANNEL=develop bash <(curl -sL https://gitlab.com/pantacor/pvr/-/raw/master/install.sh)

# Install to a custom directory
PVR_INSTALL_DIR=/usr/local/bin bash <(curl -sL https://gitlab.com/pantacor/pvr/-/raw/master/install.sh)
```

Windows PowerShell equivalents:
```powershell
# Specific version
$env:PVR_VERSION="046"; .\install.ps1

# Develop channel
$env:PVR_CHANNEL="develop"; .\install.ps1

# Custom directory
$env:PVR_INSTALL_DIR="C:\tools\pvr"; .\install.ps1
```

### Pre-built Binaries

Pre-built binaries are also available for various architectures on the [GitLab package registry](https://gitlab.com/pantacor/pvr/-/packages). You can download the binary suitable for your operating system and architecture, extract it, and place it in your system's PATH.

### Build from Source

If you prefer to build `pvr` from source, ensure you have Go 1.21+ installed:

```bash
git clone https://gitlab.com/pantacor/pvr.git
cd pvr
go build -o ~/bin/pvr ./cmd/pvr
```

### Verify Installation
```bash
pvr --help
```

## Essential Commands

### Repository Management

#### Initialize Repository
```bash
# Create a new Pantavisor repository
pvr init
```

#### Clone Device
```bash
# Clone an existing device configuration
pvr clone http://192.168.1.122:12368/cgi-bin my-checkout
pvr clone http://DEVICE_IP:12368/cgi-bin my-device
```

#### Stage and Commit Changes
```bash
# Stage all changes
pvr add .

# Commit with message
pvr commit -m "Updated configuration"

# Stage and commit in one step
pvr add . && pvr commit -m "Added new application"
```

### Application Management

#### Add Applications
```bash
# Add container from Docker Hub
pvr app add --from nginx:stable-alpine webserver

# Pick the target architecture explicitly — usually needed when adding
# images for an ARM device from an x86 workstation
pvr app add --from nginx:stable-alpine --platform linux/arm64 webserver

# Set the container's run.json fields at creation time instead of
# hand-editing them afterward
pvr app add --from nginx:stable-alpine --group app --status-goal STARTED webserver
```

`pvr app add` also accepts:

- `--group <name>` — startup group to install into (default: the last group
  in `groups.json`, if one exists).
- `--status-goal <goal>` — one of `MOUNTED`, `STARTED`, or `READY`; see
  [Status goal](/meta-pantavisor/overview/glossary#status-goal).
- `--restart-policy <policy>` — `system` or `container`; see [Restart policy](/meta-pantavisor/overview/glossary#restart-policy).
- `--runlevel <level>` — **deprecated**, use `--group` instead. Old valid
  values were `data`, `root`, `platform`, and `app`.

#### List Applications
```bash
# Show all applications in repository
pvr app ls
```

#### Update Applications
```bash
# Update existing application
pvr app update nginx-app

# Update with new image version
pvr app update app-name --from new-image:tag
```

`pvr app update` only stages the change locally, same as `pvr app add` — stage,
commit, and post it like any other change:

```bash
pvr add .
pvr commit -m "update app-name to new-image:tag"
pvr post http://<device-ip>:12368
```

#### Remove Applications
```bash
# Remove application from repository
pvr app rm app-name
```

### Device Operations

#### Local network
```bash
# Scan for Pantavisor devices on the local network (mDNS)
pvr device scan
```

Example output:

```
── Device 1 ───────────────────────────────
	ID: 1234abcd5678ef90 (unclaimed)
	Host: raspberrypi.local.
	IPv4: [192.168.1.42]
	IPv6: []
	Port: 12368
```

The `IPv4` address is `<device-ip>` — the value `pvr clone`, `pvr post`, and
the other commands on this page that take `http://<device-ip>:12368/...`
expect.

#### Pantacor Hub (requires `pvr login`)

These commands talk to the Pantahub cloud API, so you must be logged in
(`pvr login`) and the device must be claimed:

```bash
# Create a new device
pvr device create mydevice1

# Get device information
pvr device get DEVICE_ID

# Retrieve logs for a device
pvr device logs <device-nick>

# Only errors
pvr device logs -l ERROR <device-nick>

# List your devices and their status
pvr device ps
```

### Deployment

#### Post a revision to a device

`pvr post <endpoint>` sends your committed revision to a device's pvr endpoint —
either a device on the local network or a Pantahub-managed device. This is the
command that actually pushes an update to a device.

```bash
# Local network (the same endpoint you cloned from)
pvr post http://DEVICE_IP:12368

# Pantahub-managed device
pvr post https://pvr.pantahub.com/USERNAME/DEVICE_NAME
```

#### Assemble a deploy directory with `pvr deploy`

`pvr deploy <deploy-dir> [source-repos]+` composes one or more source repos into
a local deployment directory (such as `trails/0`). It builds the directory on
disk; it does **not** push to a device — use `pvr post` for that.

```bash
# Assemble the current repo into trails/0
pvr deploy trails/0 .

# Assemble from a specific repo path
pvr deploy trails/0 /path/to/repo

# Compose from multiple sources (os from a repo, bsp from an export)
pvr deploy trails/0 /path/to/repo/.pvr#os /tmp/export.tgz#bsp
```

### Signature Management

#### List Signatures
```bash
# Show signatures
pvr sig ls

# Show signatures with full JOSE serialization
pvr sig ls --with-sigs
```

#### Add Signatures
```bash
# Add signature to component
pvr sig add --part component-name
pvr sig add --part nginx

# show the full JOSE envelope incl. payload for one component
pvr sig --with-payload ls --with-sigs <component>
```

## Configuration

### Global Configuration
```bash
# Set global configuration options
pvr global-config KEY=VALUE

# Set development distribution
pvr global-config DistributionTag=develop
```

### Repository Configuration
Configuration files are stored in the `.pvr/` directory within your repository.

## Common Usage Patterns

### Complete Application Workflow
```bash
# 1. Initialize or clone repository
pvr init
# OR
pvr clone http://DEVICE_IP:12368/cgi-bin my-project

# 2. Navigate to repository
cd my-project

# 3. Add application
pvr app add --from nginx:latest web-server

# 4. Stage and commit
pvr add .
pvr commit -m "Added nginx web server"

# 5. Post to the device
pvr post http://DEVICE_IP:12368
```

### Device Configuration Workflow
```bash
# 1. Scan for devices
pvr device scan

# 2. Clone device for editing
pvr clone http://192.168.1.100:12368/cgi-bin my-device

# 3. Make configuration changes
cd my-device
# Edit files or add applications

# 4. Commit changes
pvr add .
pvr commit -m "Updated device configuration"

# 5. Post back to the device
pvr post http://DEVICE_IP:12368
```

## Tips and Best Practices

### Network Discovery
- Use `pvr device scan` to find Pantavisor devices on your network
- Devices typically expose their management interface on port 12368

### Version Control
- Always commit changes with descriptive messages
- Use `pvr add .` to stage all changes before committing
- Repository history is maintained like Git

### Application Management
- Applications are pulled from Docker Hub by default
- Use specific tags (e.g., `nginx:1.21-alpine`) instead of `latest` for production
- Test applications locally before deploying to production devices

### Deployment Strategy
- Test deployments on development devices first
- Use signature management for production deployments
- Monitor device logs after deployment

## Official Documentation

For complete command reference and advanced usage:
- `pvr help` / `pvr help <command>` - Built-in command reference
- **[PVR CLI Reference](https://docs.pantahub.com/pvr/)** - Legacy Pantahub documentation