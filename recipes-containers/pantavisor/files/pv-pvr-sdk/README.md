# pvr-sdk

pvr-sdk is the Pantavisor management service that runs inside the device as an LXC container.
It provides the on-device counterpart to the `pvr` CLI tool, handling secure OTA updates,
device registration, and Pantahub communication.

## Repository

- Source: <https://gitlab.com/pantacor/pv-platforms/pvr-sdk>
- Issues: <https://gitlab.com/pantacor/pvr-sdk/issues>

## Overview

pvr-sdk runs as a persistent system service under Pantavisor supervision. It:

- Connects to Pantahub to receive OTA update payloads
- Applies and rolls back pvr state revisions
- Manages secure storage for device credentials
- Exposes a local HTTP API used by pantavisor to coordinate updates

## Configuration

The service configuration lives at `/config/pvr-sdk/etc/pvr-sdk/config.json` inside the
container and is initialised from `_config/pvr-sdk/etc/pvr-sdk/config.json` in the pvroot.

Default listen address: `0.0.0.0:12368`
