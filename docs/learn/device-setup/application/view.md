+++
title = "View Installed Applications"
weight = 42

# SEO Configuration
description = "Monitor and manage installed applications on Pantavisor Linux. Learn to check status, start/stop apps, and view application details."
keywords = ["view pantavisor apps", "application status", "manage containers", "pvr app list", "app monitoring", "container management", "installed applications", "application control", "pantavisor management", "device app status"]
meta_description = "View Installed Applications: Monitor and manage your Pantavisor Linux applications. Check status, control app lifecycle, and view details."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "View and Manage Installed Applications on Pantavisor"
og_description = "Learn to monitor and manage installed applications on your Pantavisor Linux device. Complete guide to application lifecycle management."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Manage Pantavisor Applications"
twitter_description = "Monitor and control your containerized applications on embedded Linux devices"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.7
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/device-setup/view-installed-applications/"
+++

You can inspect running containers, their health state, and their logs from the device console, the `pvcontrol` CLI, or the pvtx local web UI.

## Quick Container List

On the device console (serial or SSH), `lxc-ls -f` shows all containers and their LXC state:

```bash
lxc-ls -f
```

Example output:

```
NAME            STATE   AUTOSTART GROUPS IPV4 IPV6 UNPRIVILEGED
bsp             RUNNING 0         -      -    -    false
network         RUNNING 0         -      -    -    false
sensor-app      RUNNING 0         -      -    -    false
```

## Full Device Status with pvcontrol

`pvcontrol ls` shows the Pantavisor view of each container, including auto-recovery counters and group membership:

```bash
pvcontrol ls
```

More targeted sub-commands:

```bash
pvcontrol container ls          # containers and their Pantavisor status
pvcontrol daemons ls            # long-running daemon containers
pvcontrol groups ls             # container groups and their restart policy
pvcontrol graph ls              # active pv-xconnect service mesh links
pvcontrol buildinfo             # Pantavisor build and revision info
```

`pvcontrol container stop <name>` and `pvcontrol container start <name>` let you stop or restart individual containers without deploying a new revision — useful during development.

## Viewing Logs

Pantavisor writes container console output and LXC logs to the storage partition. On a running device the paths are:

| Log | Path |
|-----|------|
| Pantavisor runtime | `/run/pantavisor/pv/logs/0/pantavisor/pantavisor.log` |
| Container console | `/run/pantavisor/pv/logs/0/<container>/lxc/console.log` |
| LXC internal log | `/run/pantavisor/pv/logs/0/<container>/lxc/lxc.log` |

Tail a container's console log in real time:

```bash
tail -f /run/pantavisor/pv/logs/0/sensor-app/lxc/console.log
```

Check the Pantavisor runtime log for OTA update progress or auto-recovery events:

```bash
tail -f /run/pantavisor/pv/logs/0/pantavisor/pantavisor.log
```

## Using the pvtx Web UI

The pvtx UI is served directly from the device on port **12368**. Open a browser and navigate to:

```
http://<device-ip>:12368/app
```

The homepage shows all running containers and the current revision state. You can also view the revision history and initiate configuration transitions from this interface.

![list of containers](/images/pvtx-ui-containers.png)
