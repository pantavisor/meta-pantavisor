#!/usr/bin/env python3
"""Export a kernel .config from Ubuntu kernel 'annotations' (FORMAT 4).

Reads the files as data only. Resolves include chains, merges per-key policy
dicts (child overrides parent), then looks up a value for a flavour, falling
back to its FLAVOUR_DEP and then to its arch. '-' means "leave undefined".

Ubuntu's own debian/scripts/misc/annotations does the same, but needs the full
packaging tree; this only needs the annotations files, e.g. for a DGX Spark
kernel bump:

  annotations2config.py <NV-Kernels>/debian.nvidia-7.0/config/annotations \\
      arm64 arm64-nvidia > recipes-kernel/linux/linux-nvidia-dgx/defconfig
"""
import ast
import os
import re
import sys

LINE = re.compile(r'^(CONFIG_\w+)\s+policy<(\{.*\})>\s*$')
INCLUDE = re.compile(r'^include\s+"([^"]+)"')


def parse(path, cfg, header):
    base = os.path.dirname(path)
    with open(path) as f:
        for raw in f:
            line = raw.rstrip('\n')
            m = INCLUDE.match(line)
            if m:
                parse(os.path.normpath(os.path.join(base, m.group(1))), cfg, header)
                continue
            if line.startswith('# FLAVOUR_DEP:'):
                header['dep'] = ast.literal_eval(line.split(':', 1)[1].strip())
                continue
            m = LINE.match(line)
            if m:
                cfg.setdefault(m.group(1), {}).update(ast.literal_eval(m.group(2)))


def main():
    path, arch, flavour = sys.argv[1:4]
    cfg, header = {}, {'dep': {}}
    parse(path, cfg, header)
    chain = [flavour, header['dep'].get(flavour), arch]
    out = []
    for name in sorted(cfg):
        pol = cfg[name]
        val = next((pol[k] for k in chain if k and k in pol), None)
        if val is None or val == '-':
            continue
        if val == 'n':
            out.append('# %s is not set' % name)
        else:
            out.append('%s=%s' % (name, val))
    sys.stdout.write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()
