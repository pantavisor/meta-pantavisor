#!/usr/bin/env python3
import json, sys

base_path, fragment_path, out_path = sys.argv[1:]

with open(base_path) as f:
    base = json.load(f)

with open(fragment_path) as f:
    fragment = json.load(f)

if "disks" in fragment:
    base["disks"] = fragment["disks"]

if "volumes" in fragment:
    base.setdefault("volumes", {}).update(fragment["volumes"])

with open(out_path, "w") as f:
    json.dump(base, f, indent=4)

