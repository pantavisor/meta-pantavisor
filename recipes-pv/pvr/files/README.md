# pvr

pvr is the Pantavisor command-line tool for managing Pantavisor-based devices.
It interacts with Pantahub and the on-device pvr-sdk service to inspect state,
push updates, and manage containers.

## Repository

- Source: <https://gitlab.com/pantacor/pvr>
- Issues: <https://gitlab.com/pantacor/pvr/-/issues>

## Basic usage

```sh
# Claim a device
pvr claim <device-id>

# Push a local state to the device
pvr push

# Pull the current device state
pvr pull

# List running containers
pvr ps
```

## Further reading

Full documentation is at <https://docs.pantahub.com>.
