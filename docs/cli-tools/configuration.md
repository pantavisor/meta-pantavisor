---
title: "Configuration"
description: "File formats and repository structure reference"
lead: "Understanding Pantavisor configuration files, JSON formats, and repository organization"
date: 2025-09-14T00:00:00+00:00
lastmod: 2025-09-14T00:00:00+00:00
draft: false
images: []
weight: 250
toc: true
---

## Repository Structure

Understanding the layout and organization of Pantavisor repositories.

### Standard Repository Layout

```
my-pantavisor-repo/
├── _config/              # Device configuration
│   ├── device.json       # Device-level settings
│   ├── network.json      # Network configuration
│   └── system.json       # System settings
├── containers/           # Container definitions
│   ├── app-name/         # Application container
│   │   ├── config.json   # Container configuration
│   │   └── volumes/      # Container volumes
│   ├── web-server/       # Web server container
│   └── database/         # Database container
├── volumes/              # Persistent data volumes
│   ├── app-data/         # Application data
│   ├── logs/             # Log files
│   └── config/           # Configuration data
├── .pvr/                 # PVR metadata
│   ├── config            # Repository configuration
│   ├── index             # File index
│   └── objects/          # Version objects
└── pvr.json             # Repository manifest
```

### Key Directories

#### `_config/`
Device-level configuration files that apply to the entire system.

#### `containers/`
Individual container definitions and their specific configurations.

#### `volumes/`
Persistent storage volumes that survive container updates.

#### `.pvr/`
PVR version control metadata (similar to `.git/` in Git repositories).

## Configuration File Formats

### Application Container JSON

Basic container configuration format:

```json
{
  "template": "builtin-lxc-docker",
  "args": {
    "OCI_CONFIG_PATH": "/containers/app-name"
  }
}
```

#### Advanced Container Configuration

```json
{
  "template": "builtin-lxc-docker",
  "args": {
    "OCI_CONFIG_PATH": "/containers/web-server",
    "LXC_ROOTFS_PATH": "/volumes/web-data",
    "ENV_VARS": {
      "NGINX_PORT": "80",
      "WORKER_PROCESSES": "auto"
    }
  },
  "volumes": [
    {
      "source": "/volumes/web-config",
      "target": "/etc/nginx",
      "readonly": true
    },
    {
      "source": "/volumes/web-logs",
      "target": "/var/log/nginx",
      "readonly": false
    }
  ]
}
```

### Device Configuration JSON

System-wide device settings:

```json
{
  "device": {
    "name": "production-device-01",
    "description": "Production web server",
    "location": "datacenter-east"
  },
  "network": {
    "hostname": "prod-web-01",
    "domain": "example.com"
  },
  "system": {
    "timezone": "UTC",
    "locale": "en_US.UTF-8"
  }
}
```

### Network Configuration

Network interface configuration:

```json
{
  "interfaces": {
    "eth0": {
      "method": "static",
      "address": "192.168.1.100",
      "netmask": "255.255.255.0",
      "gateway": "192.168.1.1",
      "dns": ["8.8.8.8", "8.8.4.4"]
    },
    "wlan0": {
      "method": "dhcp",
      "wireless": {
        "ssid": "MyNetwork",
        "psk": "password"
      }
    }
  }
}
```

## Container Templates

### Built-in Templates

#### `builtin-lxc-docker`
Standard template for Docker-based containers:

```json
{
  "template": "builtin-lxc-docker",
  "args": {
    "OCI_CONFIG_PATH": "/containers/my-app"
  }
}
```

#### `builtin-lxc-system`
Template for system-level containers:

```json
{
  "template": "builtin-lxc-system",
  "args": {
    "SYSTEM_CONFIG_PATH": "/containers/system-service",
    "INIT_SYSTEM": "systemd"
  }
}
```

### Custom Templates

Define custom container templates:

```json
{
  "template": "custom-web-app",
  "args": {
    "APP_PORT": "3000",
    "DB_CONNECTION": "postgresql://localhost:5432/myapp",
    "LOG_LEVEL": "info"
  },
  "volumes": [
    {
      "source": "/volumes/app-config",
      "target": "/app/config"
    }
  ],
  "environment": {
    "NODE_ENV": "production",
    "API_KEY": "${API_KEY}"
  }
}
```

## Volume Configuration

### Volume Types

#### Persistent Volumes
Data that survives container updates:

```json
{
  "volumes": {
    "database-data": {
      "type": "persistent",
      "path": "/volumes/db-data",
      "backup": true
    }
  }
}
```

#### Configuration Volumes
Configuration files and settings:

```json
{
  "volumes": {
    "app-config": {
      "type": "config",
      "path": "/volumes/app-config",
      "readonly": true
    }
  }
}
```

#### Temporary Volumes
Temporary storage cleared on restart:

```json
{
  "volumes": {
    "temp-cache": {
      "type": "temporary",
      "path": "/tmp/cache",
      "size_limit": "1GB"
    }
  }
}
```

## Environment Variables

### Container Environment

Set environment variables for containers:

```json
{
  "environment": {
    "DATABASE_URL": "postgresql://user:pass@db:5432/myapp",
    "REDIS_URL": "redis://cache:6379",
    "LOG_LEVEL": "info",
    "API_SECRET": "${API_SECRET}"
  }
}
```

### System Environment

System-wide environment variables:

```json
{
  "system_environment": {
    "TZ": "America/New_York",
    "LANG": "en_US.UTF-8",
    "PATH": "/usr/local/bin:/usr/bin:/bin"
  }
}
```

## Resource Limits

### Container Resources

Limit container resource usage:

```json
{
  "resources": {
    "memory": {
      "limit": "512MB",
      "reservation": "256MB"
    },
    "cpu": {
      "limit": "1.0",
      "shares": 1024
    },
    "storage": {
      "limit": "2GB"
    }
  }
}
```

### System Resources

System-wide resource management:

```json
{
  "system_resources": {
    "memory": {
      "total": "2GB",
      "containers": "1.5GB",
      "system": "512MB"
    },
    "cpu": {
      "cores": 4,
      "container_limit": 3
    }
  }
}
```

## Security Configuration

### Container Security

Security settings for containers:

```json
{
  "security": {
    "user": "appuser",
    "group": "appgroup",
    "capabilities": {
      "drop": ["ALL"],
      "add": ["NET_BIND_SERVICE"]
    },
    "readonly_rootfs": true,
    "no_new_privileges": true
  }
}
```

### System Security

System-level security configuration:

```json
{
  "system_security": {
    "firewall": {
      "enabled": true,
      "default_policy": "DROP",
      "rules": [
        {
          "port": 22,
          "protocol": "tcp",
          "action": "ACCEPT"
        },
        {
          "port": 80,
          "protocol": "tcp",
          "action": "ACCEPT"
        }
      ]
    },
    "ssh": {
      "port": 22,
      "password_auth": false,
      "key_auth": true
    }
  }
}
```

## Configuration Examples

### Web Application Stack

Complete configuration for a web application:

```json
{
  "containers": {
    "web": {
      "template": "builtin-lxc-docker",
      "image": "nginx:alpine",
      "ports": [
        {
          "host": 80,
          "container": 80
        }
      ],
      "volumes": [
        {
          "source": "/volumes/web-content",
          "target": "/usr/share/nginx/html"
        }
      ]
    },
    "app": {
      "template": "builtin-lxc-docker",
      "image": "node:16-alpine",
      "environment": {
        "NODE_ENV": "production",
        "PORT": "3000"
      },
      "volumes": [
        {
          "source": "/volumes/app-code",
          "target": "/app"
        }
      ]
    },
    "database": {
      "template": "builtin-lxc-docker",
      "image": "postgres:13-alpine",
      "environment": {
        "POSTGRES_DB": "myapp",
        "POSTGRES_USER": "appuser",
        "POSTGRES_PASSWORD": "${DB_PASSWORD}"
      },
      "volumes": [
        {
          "source": "/volumes/db-data",
          "target": "/var/lib/postgresql/data"
        }
      ]
    }
  }
}
```

### IoT Sensor Device

Configuration for an IoT sensor device:

```json
{
  "device": {
    "type": "iot-sensor",
    "location": "factory-floor-a",
    "sensors": ["temperature", "humidity", "pressure"]
  },
  "containers": {
    "sensor-collector": {
      "template": "builtin-lxc-docker",
      "image": "sensor-app:latest",
      "environment": {
        "SENSOR_INTERVAL": "30",
        "MQTT_BROKER": "mqtt://broker.example.com:1883"
      },
      "devices": [
        "/dev/ttyUSB0"
      ]
    },
    "edge-processing": {
      "template": "builtin-lxc-docker",
      "image": "tensorflow-lite:arm64",
      "resources": {
        "memory": "256MB",
        "cpu": "0.5"
      }
    }
  }
}
```

## Best Practices

### Configuration Management
- Use version control for all configuration changes
- Keep sensitive data in environment variables
- Document configuration changes with commit messages

### File Organization
- Group related containers in subdirectories
- Use descriptive names for volumes and containers
- Maintain consistent naming conventions

### Security
- Never store passwords in configuration files
- Use environment variables for secrets
- Apply principle of least privilege for container permissions

### Performance
- Set appropriate resource limits
- Use readonly volumes when possible
- Monitor resource usage and adjust limits accordingly

This configuration reference provides the foundation for understanding and managing Pantavisor systems effectively.