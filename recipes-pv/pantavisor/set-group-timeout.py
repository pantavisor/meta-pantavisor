#!/usr/bin/env python3
# Set every group's "timeout" in a device.json to the given seconds.
import json, sys

path, timeout = sys.argv[1], int(sys.argv[2])

with open(path) as f:
    device = json.load(f)

for group in device.get("groups", []):
    group["timeout"] = timeout

with open(path, "w") as f:
    json.dump(device, f, indent=4)
