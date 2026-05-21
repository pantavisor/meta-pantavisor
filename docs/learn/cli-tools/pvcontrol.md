---
title: "pvcontrol"
description: "Low-level system control interface"
lead: "System control and monitoring tool for Pantavisor devices"
date: 2025-09-14T00:00:00+00:00
lastmod: 2025-09-14T00:00:00+00:00
draft: false
images: []
weight: 230
toc: true
---

## Overview

**pvcontrol** provides low-level interaction with the Pantavisor control socket. It's a CLI tool that communicates with Pantavisor's HTTP control interface for monitoring, controlling, and debugging Pantavisor devices at the system level.

## Basic Usage

### List Containers
```bash
# List installed containers and their status
pvcontrol
```

This command shows the current state of all containers and their status by communicating with the `/containers` endpoint.

## Control Socket Operations

pvcontrol communicates with Pantavisor through HTTP endpoints on the control socket. The main operations include:

### Container Information
```bash
# List all containers and their status
pvcontrol

# This is equivalent to:
# curl -X GET --unix-socket /pantavisor/pv-ctrl "http://localhost/containers"
```

### System Commands
pvcontrol can send commands to the Pantavisor engine for system operations like:
- Device reboot/poweroff
- Revision transitions
- Metadata updates
- Factory reset operations

Note: Specific command syntax depends on the pvcontrol implementation and control socket endpoints.

## Alternative: Direct Control Socket Access

You can also interact directly with the control socket using cURL:

### Container Status
```bash
# Get container information
curl -X GET --unix-socket /pantavisor/pv-ctrl "http://localhost/containers"
```

### System Commands
```bash
# Send device reboot command
curl -X POST --header "Content-Type: application/json" \
  --data '{"cmd":"REBOOT_DEVICE"}' \
  --unix-socket /pantavisor/pv-ctrl \
  "http://localhost/commands"
```

### Signal Containers
```bash
# Send ready signal to container
curl -X POST --header "Content-Type: application/json" \
  --data '{"type":"ready","payload":""}' \
  --unix-socket /pantavisor/pv-ctrl \
  "http://localhost/signal"
```

## Integration with Other Tools

### With PVR CLI
```bash
# Check container state before deployment
pvcontrol

# Deploy changes
pvr deploy trails/0 .

# Verify deployment results
pvcontrol
```

## Use Cases

### System Monitoring
```bash
# Check container status periodically
while true; do
    pvcontrol
    sleep 30
done
```

### Container Debugging
```bash
# Check container status for troubleshooting
pvcontrol

# For detailed debugging, use direct control socket:
curl -X GET --unix-socket /pantavisor/pv-ctrl "http://localhost/containers"
```

### Pre-deployment Checks
```bash
# Verify container state before updates
pvcontrol

# Check for any container issues
pvcontrol | grep -i error
```

## Advanced Usage

### Scripting with pvcontrol
```bash
#!/bin/bash
# Container status check script
STATUS=$(pvcontrol)
if [[ $? -ne 0 ]]; then
    echo "Container status check failed"
    exit 1
fi
echo "Containers are running"
```

### Control Socket Integration
For advanced use cases, interact directly with the control socket endpoints documented in the official Pantavisor control socket reference.

## Best Practices

### System Monitoring
- Regularly check container status with `pvcontrol`
- Monitor container health before making changes
- Use control socket endpoints for detailed information

### Debugging
- Start with `pvcontrol` to get container overview
- Use direct control socket access for detailed debugging
- Check container status changes after deployments

### Integration
- Combine with PVR for comprehensive device management
- Use in scripts for automated monitoring
- Integrate with control socket for custom monitoring

## Common Scenarios

### Check Container Status
```bash
pvcontrol
```

### Verify Deployment
```bash
# Before deployment
pvcontrol

# After deployment
pvcontrol
# Check for any status changes
```

### Control Socket Access
```bash
# Direct container information
curl -X GET --unix-socket /pantavisor/pv-ctrl "http://localhost/containers"
```

## Official Documentation

For complete command reference:
- **[Pantavisor Control Socket](https://docs.pantahub.com/pantavisor-commands/)** - Complete control interface documentation
- **[Local Control Guide](https://docs.pantahub.com/local-control/)** - Device management overview