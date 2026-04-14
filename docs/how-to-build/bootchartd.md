# Bootchartd

Pantavisor supports [bootchartd](https://github.com/mmeeks/bootchart) for boot time profiling. When enabled, Pantavisor generates a `bootchartd.tgz` tarball capturing the boot sequence.

## Enable

Add `bootchartd` to `PANTAVISOR_FEATURES` in your distro config or recipe:

```bitbake
PANTAVISOR_FEATURES:append = " bootchartd"
```

This enables the following Busybox options:
- `CONFIG_TAR`
- `CONFIG_FEATURE_TAR_CREATE`
- `CONFIG_BOOTCHARTD`

## Pantavisor-specific patch

Bootchartd normally writes data to `/tmp` and `/var/log`, which are not available in the Pantavisor initramfs. The meta-pantavisor layer includes a patch redirecting all output to the root directory `/` instead.

## Usage

Boot with `rdinit=/sbin/bootchartd` to generate the tarball:

```
# In your bootloader or kernel cmdline:
rdinit=/sbin/bootchartd
```

The resulting `bootchartd.tgz` can be analysed with standard bootchart tools.
