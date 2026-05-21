---
title: "Common Workflows"
description: "Step-by-step guides for frequent Pantavisor tasks"
lead: "Practical workflows for application deployment, device management, and system configuration"
date: 2025-09-14T00:00:00+00:00
lastmod: 2025-09-14T00:00:00+00:00
draft: false
images: []
weight: 240
toc: true
---

## Application Management Workflows

### 1. Adding a New Application

Complete workflow for adding and deploying a new containerized application.

```bash
# Navigate to your Pantavisor repository
cd my-pantavisor-project

# Add application from Docker Hub
pvr app add --from nginx:latest web-server

# Stage and commit changes
pvr add .
pvr commit -m "Added nginx web server"

# Deploy to device
pvr deploy trails/0 .
```

#### Variations

**Add Database Application:**
```bash
pvr app add --from postgres:13 database
pvr add . && pvr commit -m "Added PostgreSQL database"
pvr deploy trails/0 .
```

**Add with Custom Configuration:**
```bash
pvr app add --from redis:alpine cache-server
# Edit configuration files
pvr add . && pvr commit -m "Added Redis cache with custom config"
pvr deploy trails/0 .
```

### 2. Updating Existing Applications

Update application versions and configurations.

```bash
# List current applications
pvr app ls

# Update container version
pvr app update app-name --from new-image:tag

# Stage and commit
pvr add .
pvr commit -m "Updated app-name to new version"

# Deploy changes
pvr deploy trails/0 .
```

### 3. Removing Applications

Safely remove applications from your system.

```bash
# Remove application
pvr app rm app-name

# Commit removal
pvr add .
pvr commit -m "Removed app-name application"

# Deploy changes
pvr deploy trails/0 .
```

## Device Management Workflows

### 1. Initial Device Setup

Set up a new Pantavisor device from scratch.

```bash
# Scan network for devices
pvr device scan

# Clone device for initial configuration
pvr clone http://DEVICE_IP:12368/cgi-bin/pvr my-device

# Navigate to device repository
cd my-device

# Configure device settings manually
# Edit run.json or other configuration files
vi run.json

# Commit changes
pvr add .
pvr commit -m "Updated device configuration"
```

### 2. Device Configuration Updates

Update device configuration remotely.

```bash
# Clone device for editing
pvr clone http://DEVICE_IP:12368/cgi-bin/pvr device-config

# Edit configuration files
cd device-config
# Modify settings, network config, etc.

# Commit changes
pvr add .
pvr commit -m "Updated device configuration"

# Deploy back to device
pvr deploy trails/0 .
```

### 3. Multi-Device Management

Manage multiple devices with consistent configuration.

```bash
# Create base configuration repository
pvr init multi-device-config
cd multi-device-config

# Add common applications
pvr app add --from nginx:stable web-server
pvr app add --from node:alpine app-runtime

# Commit base configuration
pvr add . && pvr commit -m "Base device configuration"

# Deploy to multiple devices
for device in device1 device2 device3; do
    pvr deploy trails/0 . --device $device
done
```

## Development Workflows

### 1. Local Development and Testing

Develop and test applications locally before deployment.

```bash
# Clone production device for testing
pvr clone http://PROD_DEVICE:12368/cgi-bin/pvr test-environment

# Add development applications
cd test-environment
pvr app add --from my-app:dev development-app

# Test deployment on development device
pvr add . && pvr commit -m "Added development application"
pvr deploy trails/0 . --device DEV_DEVICE

# After testing, deploy to production
pvr deploy trails/0 . --device PROD_DEVICE
```

### 2. Configuration Testing

Test configuration changes safely.

```bash
# Create configuration branch
pvr clone http://DEVICE_IP:12368/cgi-bin/pvr config-test

# Make experimental changes
cd config-test
# Edit configuration files manually
vi run.json

# Commit changes
pvr add .
pvr commit -m "Test configuration changes"

# Test on development device
pvr deploy trails/0 . --device DEV_DEVICE

# If successful, apply to production
pvr deploy trails/0 . --device PROD_DEVICE
```

### 3. Application Development Cycle

Complete development cycle for custom applications.

```bash
# 1. Initial setup
pvr init my-app-development
cd my-app-development

# 2. Add base system
pvr app add --from ubuntu:20.04 base-system

# 3. Add development tools
pvr app add --from node:16 development-env

# 4. Iterative development
while developing; do
    # Make code changes
    # Update container
    pvr app update development-env --from my-app:latest

    # Test deployment
    pvr add . && pvr commit -m "Development iteration"
    pvr deploy trails/0 . --device DEV_DEVICE

    # Verify and continue
done

# 5. Production deployment
pvr app update development-env --from my-app:stable
pvr add . && pvr commit -m "Production release"
pvr deploy trails/0 . --device PROD_DEVICE
```

## Maintenance Workflows

### 1. System Health Monitoring

Regular system health checks and maintenance.

```bash
# Check device status
pvr device scan
pvr device ps

# Clone device for inspection
pvr clone http://DEVICE_IP:12368/cgi-bin/pvr health-check

# Check system health on device
pvcontrol status
pvcontrol logs

# Check application status
pvcontrol ls
pvr app ls
```

### 2. Security Updates

Apply security updates to devices.

```bash
# Update base system images
pvr app update base-system --from ubuntu:20.04-security

# Update application images
pvr app update web-server --from nginx:stable-alpine

# Stage and commit updates
pvr add .
pvr commit -m "Security updates applied"

# Deploy to devices
pvr deploy trails/0 .
```

### 3. Backup and Recovery

Backup device configurations and applications.

```bash
# Backup device configuration
pvr clone http://DEVICE_IP:12368/cgi-bin/pvr backup-$(date +%Y%m%d)

# Create recovery image
cd backup-$(date +%Y%m%d)
tar -czf device-backup-$(date +%Y%m%d).tar.gz .

# Recovery process
tar -xzf device-backup-YYYYMMDD.tar.gz
cd device-backup-YYYYMMDD
pvr deploy trails/0 . --device RECOVERY_DEVICE
```

## Troubleshooting Workflows

### 1. Application Debugging

Debug failing applications systematically.

```bash
# Check application status
pvr device ps
pvcontrol ls

# Get application logs
pvcontrol logs failing-app

# Inspect application configuration
pvcontrol inspect failing-app

# Clone device for detailed inspection
pvr clone http://DEVICE_IP:12368/cgi-bin/pvr debug-session

# Make fixes
cd debug-session
# Edit configuration or update application
pvr add . && pvr commit -m "Fixed application issue"
pvr deploy trails/0 .
```

### 2. Network Connectivity Issues

Diagnose and fix network problems.

```bash
# Check device connectivity
pvr device scan

# Clone device state to inspect configuration
pvr clone http://DEVICE_IP:12368/cgi-bin/pvr debug-network

cd debug-network
# Check and fix network configuration manually
vi bsp/run.json

# Commit and deploy fixes
pvr add .
pvr commit -m "Fix network configuration"
pvr deploy trails/0 .
```

### 3. System Recovery

Recover from system failures.

```bash
# Check system status
pvcontrol status
pvcontrol logs

# Attempt service restart
pvcontrol restart failing-service

# If restart fails, rollback to previous state
pvr deploy trails/1 .  # Deploy previous revision

# Monitor recovery
pvcontrol status
pvcontrol ls
```

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
- Regularly check device status with `pvr device ps`
- Monitor application logs with `pvcontrol logs`
- Set up automated health checks

These workflows provide tested patterns for common Pantavisor operations. Adapt them to your specific use cases and requirements.