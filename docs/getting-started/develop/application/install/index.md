---
title: Install apps
sidebar_position: 20
description: Install applications on Pantavisor as LXC containers — using the pvr CLI over the local network, the pvtx web UI, or remotely via Pantahub.
---

Every application on a Pantavisor device is an LXC container added to the device's revision trail. There are three ways to install a new container, depending on whether you want a command-line-only workflow, a local web upload, or cloud-based remote management.

---

### 1. pvr CLI over the Local Network

The `pvr` CLI is the primary tool for managing device state. You clone the device, add a container from a Docker Hub image or a pvrexport bundle, commit, and deploy — all from your workstation over the local network. This is the recommended method for development and automation.

→ [Install with pvr CLI](./local-pvr/)

### 2. pvtx Web UI over the Local Network

The pvtx interface is served directly from the device on port 12368. You build a container package on your workstation using `pvr`, export it as a `.tar.gz` archive, then upload it through the browser UI and commit the transaction from there. Useful for one-off installs without setting up a full pvr workflow.

→ [Install via pvtx](./local-pvtx/)

### 3. Remotely via Pantahub

If the device is registered with [Pantahub](https://hub.pantacor.com), you can push updates from anywhere. Claim the device in your Pantahub account, upload the container package through the Pantahub dashboard, and commit the transaction. The device pulls the new revision from the cloud and applies it automatically.

→ [Install via Pantahub](./remote-pantahub/)