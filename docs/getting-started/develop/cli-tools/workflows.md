---
title: Common Workflows
description: Step-by-step guides for frequent Pantavisor tasks
---

## Application Management Cheatsheet

The canonical guides are [Install applications](/meta-pantavisor/getting-started/develop/application/install/local-pvr),
[Configure applications](/meta-pantavisor/getting-started/develop/application/configure), and
[Remove applications](/meta-pantavisor/getting-started/develop/application/remove). The short version, from
inside your `pvr` checkout:

**Add an application:**
```bash
pvr app add --from nginx:stable-alpine web-server
pvr add . && pvr commit -m "Added nginx web server"
pvr post http://DEVICE_IP:12368
```

**Update an application:**
```bash
pvr app update web-server --from nginx:1.27-alpine
pvr add . && pvr commit -m "Updated web-server"
pvr post http://DEVICE_IP:12368
```

**Remove an application:**
```bash
pvr app rm web-server
pvr add . && pvr commit -m "Removed web-server"
pvr post http://DEVICE_IP:12368
```

## Device Management Workflows

### 1. Initial Device Setup

Set up a new Pantavisor device from scratch.

```bash
# Scan network for devices
pvr device scan

# Clone device for initial configuration
pvr clone http://DEVICE_IP:12368/cgi-bin my-device

# Navigate to device repository
cd my-device

# Configure device settings manually
# Edit a container's run.json or other configuration files
vi <container>/run.json

# Commit changes
pvr add .
pvr commit -m "Updated device configuration"

# Deploy back to the device
pvr post http://DEVICE_IP:12368
```

### 2. Device Configuration Updates

Updating a device's configuration is the same clone → edit → commit → post loop
shown above and in the [PVR CLI guide](/meta-pantavisor/getting-started/develop/cli-tools/pvr-cli):

```bash
pvr clone http://DEVICE_IP:12368/cgi-bin device-config
cd device-config
# Edit configuration files (run.json, _config/ overlays, ...)
pvr add . && pvr commit -m "Updated device configuration"
pvr post http://DEVICE_IP:12368
```

### 3. Multi-Device Management

Manage multiple devices with consistent configuration. Start from a known-good
("golden") device so your base state already carries a working BSP, then add the
common applications and post to each target:

```bash
# Clone the golden device as the base configuration
pvr clone http://GOLDEN_DEVICE_IP:12368/cgi-bin golden
cd golden

# Add the applications every device should run
pvr app add --from nginx:stable-alpine web-server

# Commit base configuration
pvr add . && pvr commit -m "Base fleet configuration"

# Deploy to multiple devices
for device in device1 device2 device3; do
    pvr post https://pvr.pantahub.com/USERNAME/$device
done
```

## Development Workflows

### 1. Local Development and Testing

Develop and test applications locally before deployment.

```bash
# Clone production device for testing
pvr clone http://PROD_DEVICE:12368/cgi-bin test-environment

# Add development applications
cd test-environment
pvr app add --from my-app:dev development-app

# Test deployment on development device
pvr add . && pvr commit -m "Added development application"
pvr post https://pvr.pantahub.com/USERNAME/DEV_DEVICE

# After testing, deploy to production
pvr post https://pvr.pantahub.com/USERNAME/PROD_DEVICE
```

### 2. Configuration Testing

Test configuration changes safely.

```bash
# Create configuration branch
pvr clone http://DEVICE_IP:12368/cgi-bin config-test

# Make experimental changes
cd config-test
# Edit configuration files manually
vi <container>/run.json

# Commit changes
pvr add .
pvr commit -m "Test configuration changes"

# Test on development device
pvr post https://pvr.pantahub.com/USERNAME/DEV_DEVICE

# If successful, apply to production
pvr post https://pvr.pantahub.com/USERNAME/PROD_DEVICE
```

### 3. Application Development Cycle

Complete development cycle for custom applications.

```bash
# 1. Initial setup — pvr init pvr-izes the current directory
mkdir my-app-development && cd my-app-development
pvr init

# 2. Add your application container
pvr app add --from my-app:dev my-app
```

Then iterate — this is the development loop, repeated until you are happy:

1. Make code changes and rebuild your container image (`my-app:latest`).
2. Update the checkout: `pvr app update my-app --from my-app:latest`
3. Commit and post: `pvr add . && pvr commit -m "Development iteration"` then
   `pvr post https://pvr.pantahub.com/USERNAME/DEV_DEVICE`
4. Verify on the device and go back to step 1.

When the application is ready, deploy the stable image to production:

```bash
pvr app update my-app --from my-app:stable
pvr add . && pvr commit -m "Production release"
pvr post https://pvr.pantahub.com/USERNAME/PROD_DEVICE
```

## Maintenance Workflows

### 1. System Health Monitoring

Regular system health checks and maintenance.

```bash
# Find devices on the local network
pvr device scan

# Fleet listing of claimed devices (requires pvr login)
pvr device ps

# On the device: containers, status, and build info
pvcontrol ls
pvcontrol buildinfo
pvcontrol container ls
```

### 2. Security Updates

Apply security updates to devices.

```bash
# Update application images to patched versions
pvr app update web-server --from nginx:stable-alpine
pvr app update cache-server --from redis:7-alpine

# Stage and commit updates
pvr add .
pvr commit -m "Security updates applied"

# Deploy to devices
pvr post http://DEVICE_IP:12368
```

### 3. Backup and Recovery

Backup device configurations and applications.

```bash
# Backup device configuration
pvr clone http://DEVICE_IP:12368/cgi-bin backup-$(date +%Y%m%d)

# Create recovery image
cd backup-$(date +%Y%m%d)
tar -czf device-backup-$(date +%Y%m%d).tar.gz .

# Recovery process
tar -xzf device-backup-YYYYMMDD.tar.gz
cd device-backup-YYYYMMDD
pvr post https://pvr.pantahub.com/USERNAME/RECOVERY_DEVICE
```

## Troubleshooting Workflows

### 1. Application Debugging

Debug failing applications systematically.

```bash
# Check application status (on the device)
pvcontrol ls

# Get application logs (on the device)
tail /pantavisor/logs/<revision>/failing-app/lxc/console.log

# Inspect container state
pvcontrol container ls

# Clone device for detailed inspection
pvr clone http://DEVICE_IP:12368/cgi-bin debug-session

# Make fixes
cd debug-session
# Edit configuration or update application
pvr add . && pvr commit -m "Fixed application issue"
pvr post http://DEVICE_IP:12368
```

### 2. Network Connectivity Issues

Diagnose and fix network problems.

```bash
# Check device connectivity
pvr device scan

# Clone device state to inspect configuration
pvr clone http://DEVICE_IP:12368/cgi-bin debug-network

cd debug-network
# Check and fix network configuration manually
vi bsp/run.json

# Commit and deploy fixes
pvr add .
pvr commit -m "Fix network configuration"
pvr post http://DEVICE_IP:12368
```

### 3. System Recovery

Recover from system failures.

```bash
# Check system status
pvcontrol ls

# Attempt container restart
pvcontrol container restart failing-service

# If restart fails, roll back: check out the last known-good revision
# (clone it from the device or use your saved checkout) and post it
pvr post http://DEVICE_IP:12368

# Monitor recovery
pvcontrol ls
```

Note that Pantavisor automatically rolls back failed updates that never reach
their status goal — manual rollback is for revisions that came up but
misbehave.

## Best Practices

### Version Control
- Always commit changes with descriptive messages
- Use meaningful branch/revision names
- Keep track of working configurations

### Testing
- Test on development devices before production
- Monitor system health after deployments
- Keep backup configurations available

### Security
- Regularly update base images and applications
- Change default passwords immediately
- Use specific image tags instead of `latest`

### Monitoring
- Check on-device health with `pvcontrol ls` and `pvcontrol buildinfo`; use `pvr device ps` for fleet listing (requires `pvr login`)
- Monitor application logs under `/pantavisor/logs/<revision>/` on the device (or `pvr device logs` for claimed devices)
- Set up automated health checks

These workflows provide tested patterns for common Pantavisor operations. Adapt them to your specific use cases and requirements.