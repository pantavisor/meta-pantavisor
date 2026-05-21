---
title: "PVR CLI"
description: "Complete reference for the PVR command-line tool"
lead: "Essential commands and usage examples for Pantavisor's primary CLI tool"
date: 2025-09-14T00:00:00+00:00
lastmod: 2025-09-14T00:00:00+00:00
draft: false
images: []
weight: 210
toc: true
---

## Overview

The **pvr** command-line tool is your primary interface for managing Pantavisor repositories and devices. It enables repository management, application deployment, device interaction, and system configuration.

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
pvr clone http://192.168.1.122:12368/cgi-bin/pvr my-checkout
pvr clone http://DEVICE_IP:12368/cgi-bin/pvr my-device
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
pvr app add --from nginx:latest web-server
pvr app add --from postgres:13 database

# Add application with specific configuration
pvr app add --from redis:alpine cache-server
```

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

#### Remove Applications
```bash
# Remove application from repository
pvr app rm app-name
```

### Device Operations

#### Network Discovery
```bash
# Scan for Pantavisor devices on network
pvr device scan
```

#### Device Management
```bash
# Create a new device
pvr device create mydevice1

# Get device information
pvr device get DEVICE_ID

# Retrieve device logs
pvr device logs
```

### Deployment

#### Basic Deployment
```bash
# Deploy repository to device
pvr deploy trails/0 /path/to/repo

# Deploy current directory
pvr deploy trails/0 .
```

#### Advanced Deployment
```bash
# Deploy with specific configurations
pvr deploy trails/0 /path/to/repo/.pvr#os /tmp/export.tgz#bsp

# Deploy to specific device
pvr deploy trails/0 . --device DEVICE_ID
```

### Signature Management

#### List Signatures
```bash
# Show signatures
pvr sig ls

# Show signatures with full JOSE serialization
pvr sig ls --with-sig
```

#### Add Signatures
```bash
# Add signature to component
pvr sig add --part component-name
pvr sig add --part nginx

# Show signature with payload
pvr sig --with-payload ls --with-sig _sigs/awconnect.json
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
pvr clone http://DEVICE_IP:12368/cgi-bin/pvr my-project

# 2. Navigate to repository
cd my-project

# 3. Add application
pvr app add --from nginx:latest web-server

# 4. Stage and commit
pvr add .
pvr commit -m "Added nginx web server"

# 5. Deploy to device
pvr deploy trails/0 .
```

### Device Configuration Workflow
```bash
# 1. Scan for devices
pvr device scan

# 2. Clone device for editing
pvr clone http://192.168.1.100:12368/cgi-bin/pvr my-device

# 3. Make configuration changes
cd my-device
# Edit files or add applications

# 4. Commit changes
pvr add .
pvr commit -m "Updated device configuration"

# 5. Deploy back to device
pvr deploy trails/0 .
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
- **[PVR CLI Reference](https://docs.pantahub.com/pvr/)** - Official documentation
- **Installation Guide** - Download and setup