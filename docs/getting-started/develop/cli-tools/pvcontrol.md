---
title: pvcontrol
description: Query and control a running Pantavisor device from the on-device control socket — list containers and revisions, start/stop containers, read metadata, and send device commands.
---

## Overview

**pvcontrol** is the on-device CLI for the Pantavisor control socket. It talks to
the running Pantavisor (PID 1) over a Unix socket and lets you inspect device
state, control individual containers, read and write metadata, and issue
device-level commands such as reboot or garbage collection — all without cloud
connectivity.

Run it from the serial console debug shell or over SSH on the device. It is a
*runtime* control tool; to change the device's persistent state, build a new
revision with [`pvr`](/meta-pantavisor/getting-started/develop/cli-tools/pvr-cli) and post it.

## Status and inspection

```bash
# List containers — name, group, status, status goal, restart policy
pvcontrol ls

# Pantavisor build and current revision info
pvcontrol buildinfo

# Containers and their Pantavisor status
pvcontrol container ls

# Pantavisor internal daemons (e.g. pv-xconnect)
pvcontrol daemons ls

# Container groups and their restart policy
pvcontrol groups ls

# xconnect service graph (GET /xconnect-graph)
pvcontrol graph ls
```

## Container control

Start, stop, or restart a single container at runtime without deploying a new
revision — useful during development and debugging:

```bash
pvcontrol container stop <name>
pvcontrol container start <name>
pvcontrol container restart <name>
```

These changes are runtime-only. They do not alter the committed revision, so the
container returns to its declared state on the next boot. To change behaviour
permanently, edit the container's `run.json` and post a new revision — see
[Configure applications](/meta-pantavisor/getting-started/develop/application/configure).

## Revisions (steps)

```bash
# List the revisions (steps) in the device trail
pvcontrol steps ls

# Show a specific revision
pvcontrol steps get <rev>

# Install or upload a revision and watch its progress
pvcontrol steps install <rev>
pvcontrol steps put <rev> <file>
pvcontrol steps show-progress <rev>
```

Related plumbing: `pvcontrol objects ls|get|put` manages content-addressed
objects directly, and `pvcontrol config ls` dumps the running Pantavisor
configuration.

## Metadata

```bash
# Device-reported metadata (interfaces, Pantahub state, platform info)
pvcontrol devmeta ls

# User metadata key/value entries
pvcontrol usrmeta ls

# Write or remove a user metadata entry
pvcontrol usrmeta save <key> <value>
pvcontrol usrmeta delete <key>

# Same for device metadata
pvcontrol devmeta save <key> <value>
pvcontrol devmeta delete <key>
```

## Device commands

```bash
pvcontrol cmd reboot        # reboot the device
pvcontrol cmd poweroff      # power the device off
pvcontrol cmd run-gc        # run garbage collection on the object store
pvcontrol cmd enable-ssh    # enable the SSH debug access
pvcontrol cmd disable-ssh   # disable SSH debug access

pvcontrol cmd run <rev>         # run a local revision without committing it
pvcontrol cmd run-commit <rev>  # run a local revision and commit it as the rollback point
pvcontrol cmd make-factory      # mark the current revision as the factory revision
```

## Signals

Containers report readiness back to Pantavisor through signals. You can send one
manually for testing:

```bash
pvcontrol signal ready      # report the container as ready
pvcontrol signal alive      # heartbeat / liveness signal
```

## Direct control-socket access

`pvcontrol` is a thin client over an HTTP-style API exposed on the control
socket at `/run/pantavisor/pv/pv-ctrl`. You can call the endpoints directly with
`curl` (or the bundled `pvcurl`) when scripting:

```bash
# List containers
curl -X GET --unix-socket /run/pantavisor/pv/pv-ctrl \
  "http://localhost/containers"

# Read build info
curl -X GET --unix-socket /run/pantavisor/pv/pv-ctrl \
  "http://localhost/buildinfo"

# Send a device command
curl -X POST --header "Content-Type: application/json" \
  --data '{"op":"REBOOT_DEVICE","payload":""}' \
  --unix-socket /run/pantavisor/pv/pv-ctrl \
  "http://localhost/commands"
```

## Official documentation

For the complete on-device tooling reference, see
[Pantavisor tools](/pantavisor/reference/pantavisor-tools).
