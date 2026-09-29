---
title: Live logs
sidebar_position: 7
description: Stream any log file from a Pantavisor device to the Pantahub or Fleet web UI while you watch, filtered on the device before anything is sent.
---

The **Live logs** tab on a device's page (Pantahub and Fleet) streams log files from the device while the page is open: Pantavisor's own log, each container's console, and whatever a container writes under its `/var/log`. Unlike the persisted logs Pantavisor pushes, nothing is stored: lines go from the device to your browser over the device's MQTT connection, for as long as you watch and no longer.

## What you need

- A device managed by the Pantahub MQTT agent (`pv-mqtt-sdk`), connected over MQTT.
- You must be the device's owner. A token used from a script needs the full API scope or the `devices.logs` scope.

## Using it

1. Open **Live logs** on the device page. The tab asks the device which log files it has (the `LIST_LOG_SOURCES` command) and shows them as a tree: one folder per container plus `pantavisor`, with the rotated `.gz` files of each.
2. Pick what to stream, up to 10 entries:
   - a file, such as `pantavisor/pantavisor.log` or `myapp/lxc/console.log`;
   - a **folder**, which streams every live file under it (a container's whole output);
   - **All logs**, the whole revision.
   A folder streams at most 64 files; rotated `.gz` files are picked one by one, and are read once rather than followed.
3. Choose the revision. The running revision is followed live; older revisions and `.gz` files are read once.
4. Optionally type a **filter**. It is sent to the device, which then sends only the lines that contain the text (case-insensitive), so a busy device costs no bandwidth for lines you will not read. Changing the text while streaming restarts the session with the new filter; the initial tail counts matching lines.
5. Press **Start**. The last lines (200 by default) arrive first, then new ones as they are written. Pause, download what you have, or filter the view further by source.

A session ends when you leave the tab, after 30 minutes, or when the lease runs out (60 s after the tab is hidden).

## How it works

Pantavisor has no API to read logs back, so the agent reads the files itself: its container has the `mgmt` role and sees every revision's logs read-only under `/pantavisor/logs/<rev>/`. A session is a lease the browser renews every 20 seconds; the device follows the selected files across rotation, batches lines every 500 ms or 32 KiB, and sends them at most at 64 KiB/s (lines above that are counted as dropped, never buffered forever). Batches are numbered, so a gap shows in the view.

Pantahub keeps a batch for ten minutes in a TTL collection so several API replicas can serve the long-poll; nothing goes into the persisted logs.

| Limit | Value |
|---|---|
| Lease / hard limit | 60 s renewed while visible / 30 min |
| Sessions | 2 per device, 5 per user |
| Sources | 10 entries, 64 files per session |
| Tail | up to 500 lines |
| Line | cut at 8 KiB |
| Rate | 64 KiB/s per session |
| Filter | up to 256 bytes, case-insensitive substring, applied on the device |

The wire contract is [`docs/logs.md` in pv-mqtt-sdk](https://github.com/pantavisor/pv-mqtt-sdk/blob/main/docs/logs.md).
