+++
title = "Embedded web UI"
weight = 4

# SEO Configuration
description = "Learn to use the Pantavisor embedded web UI for managing applications on Pantavisor Linux. Complete guide to navigation, installation, and configuration."
keywords = ["pvtx interface", "pantavisor web ui", "application management", "pantavisor gui", "device management", "pvtx tutorial", "app installation", "pantavisor interface", "embedded device management", "container management ui"]
meta_description = "Pantavisor Web UI: Master the application management interface for Pantavisor Linux. Learn navigation, app installation, and configuration."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Pantavisor Web UI - Application Management Guide"
og_description = "Master the Pantavisor web UI for managing applications on your Pantavisor Linux device. Complete navigation and usage guide."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Pantavisor Web UI Tutorial"
twitter_description = "Learn to use the Pantavisor web UI for managing applications on embedded Linux devices"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.8
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/device-setup/device-access/pvtx-ui/"
+++

The pvtx UI is a web interface served directly from the device on port **12368**. It gives you a browser-based view of the device's running containers, revision state, system resources, configuration, and logs — without needing the `pvr` CLI or SSH.

Open a browser and navigate to:

```
http://<device-ip>:12368/app
```

---

## Home — Revision State and Transactions

The **Home** page shows the device's current revision and lets you manage software transitions.

![Home Page of Pantavisor UI](/images/pvtx-ui-home.png)

Key indicators:

- **Status**: `DONE` means the current revision is committed and stable. `TESTING` means a new revision is being evaluated.
- **Progress**: Percentage completion of the current update or boot sequence.
- **Rev**: The current revision number in the device's trail.

**Containers list**: Expandable rows show each container (BSP, OS, applications) with its name and component details.

### Uploading a Container (Transaction)

To install or update a container without the `pvr` CLI:

1. Click **Begin Transition** to open the update panel.
2. Drag and drop a `.tar.gz` container package (built with `pvr export`) into the upload area.
3. Click **Commit Transaction**.

![Transaction upload](/images/pvtx-ui-transaction.png)

Pantavisor writes the uploaded container as a new pending revision and reboots. The status updates to `DONE` once the revision is committed, or rolls back if the boot fails.

---

## Stats & Config

The **Stats & Config** page shows live resource usage and device identity.

### Device Stats

| Field | Description |
|-------|-------------|
| RAM | Used / total memory |
| Swap | Swap space usage |
| Disk usage | Storage partition used / total |
| Reserved | Space reserved by Pantavisor for revision objects |

![Stats Page of Pantavisor UI](/images/pvtx-ui-stats.png)

### Device Meta & Config

- **IP Addresses**: IPv4/IPv6 per network interface (`eth0`, `wlan0`, `lo`)
- **Pantahub status**: `pantahub.claimed` and `pantahub.online` show cloud connectivity; `pantahub.state` shows the current handshake state (`claim`, `connected`, etc.)
- **Device Config**: Key-value pairs including `creds.id` (device ID), `creds.host`/`creds.port` (Pantahub API endpoint), and `creds.prn` (Pantahub Resource Name)

![Config Page of Pantavisor UI](/images/pvtx-ui-config.png)

---

## Logs

The **Logs** page streams container and Pantavisor runtime logs directly in the browser.

- **Log selector** (left panel): Choose a container or system component. Common sources include `pantavisor` (runtime log), `pvr-sdk`, and each application container.
- **Log output** (main panel): Timestamped entries with severity levels (`DEBUG`, `INFO`, `WARN`, `ERROR`).

![Logs Page of Pantavisor UI](/images/pvtx-ui-logs.png)

This view mirrors the on-device log files at `/run/pantavisor/pv/logs/0/<container>/lxc/console.log`.