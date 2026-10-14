---
title: Build Containers with the SDK
sidebar_position: 22
description: Cross-compile an application with the Pantavisor container SDK and pack it into a signed pvrexport, without a Yocto build.
---

The Pantavisor SDK is a cross toolchain plus `pv-mkpvrexport`, a tool that
packs a root filesystem into a signed `<name>.pvrexport.tgz`, the same
package a container recipe produces in a Yocto build. Use it when your
application is not a Docker image and you don't want to set up a Yocto
build of this layer. The same SDK also
[builds Pantavisor itself](../../../overview/pantavisor-sdk.md).

## Pick the SDK for your device

Each release attaches one installer per architecture to its
[GitHub Release](https://github.com/pantavisor/meta-pantavisor/releases):

| Installer | Device CPU |
|---|---|
| `pv-sdk-<tag>-x86_64.sh` | x86_64 |
| `pv-sdk-<tag>-armv8.sh` | 64-bit ARM (aarch64) |
| `pv-sdk-<tag>-armv7.sh` | 32-bit ARM, armv7 hard-float |

The installers run on x86_64 Linux hosts. The toolchain targets musl, the C
library of the Pantavisor board images.

## Install

```bash
sh ./pv-sdk-<tag>-armv8.sh -d ~/pv-sdk-armv8 -y
. ~/pv-sdk-armv8/environment-setup-*
```

Sourcing `environment-setup-*` puts the cross compiler (`$CC`, `$CXX`,
`$CONFIGURE_FLAGS`, ...) and `pv-mkpvrexport` on `PATH` for this shell.

## Build a container

Install your application into a directory laid out like the container's
root filesystem, then pack it. `--base` lays that directory over the SDK's
base rootfs (busybox, plus the C library, `libgcc` and `libstdc++` the
toolchain links against), so a dynamically linked C or C++ binary finds its
libraries:

```bash
cat > hello.c <<'EOF'
#include <stdio.h>
#include <unistd.h>
int main(void) { for (;;) { puts("hello from the container SDK"); sleep(10); } }
EOF

mkdir -p rootfs/usr/bin
$CC -o rootfs/usr/bin/hello hello.c

pv-mkpvrexport --base rootfs hello -- --config=Entrypoint=/usr/bin/hello
pvr inspect hello.pvrexport.tgz
```

For autotools, CMake or Meson projects, install with
`make DESTDIR="$PWD/rootfs" install` (or the equivalent) into the same
directory.

`pv-mkpvrexport` never modifies `rootfs`. It copies it, adds the mountpoints
LXC needs, makes every file owned by root, and signs the result with the
Pantacor developer keys shipped in the SDK (`--keys` to use your own
`pvs` keys tarball). The options map to the files a container recipe
provides:

| Option | Same as, in a recipe |
|---|---|
| `--args-json FILE` | `${PN}.args.json` |
| `--config-json FILE` | `${PN}.config.json` |
| `--services-json FILE` | `${PN}.services.json` |
| `--network-json FILE` | `${PN}.network.json` |
| `--mdev-json FILE` / `--no-mdev` | `${PN}.mdev.json` / `PVRIMAGE_AUTO_MDEV = "0"` |
| `--group NAME` | `PVR_APP_ADD_GROUP` |
| `--roles "R1 R2"` | `PVR_APP_ADD_ROLES` |
| `--comp lz4` | `PANTAVISOR_FEATURES` `squash-lz4` |
| `-- <args>` | `PVR_APP_ADD_EXTRA_ARGS` |

`pv-mkpvrexport --help` lists them all.

## Deploy it

Merge the export into a checkout of the device (`pvr merge` commits it) and
post the new revision:

```bash
pvr clone http://<device-ip>:12368/cgi-bin mydevice
cd mydevice
pvr merge ../hello.pvrexport.tgz
pvr checkout
pvr post http://<device-ip>:12368
```

Or upload `hello.pvrexport.tgz` from a browser through the
[pvtx web UI](./install/local-pvtx.md#2--upload-via-pvtx).

For a device managed through Pantahub (`pantavisor.mode` is `remote`),
clone it from Pantahub instead; `pvr post` then sends the revision back
there:

```bash
pvr clone https://pvr.pantahub.com/<user>/<device-nick> mydevice
cd mydevice
pvr merge ../hello.pvrexport.tgz
pvr checkout
pvr post -m "add hello"
```

## Example: read a hardware RTC

This container reads the board's real-time clock through `/dev/rtc0` and
logs it next to the system time. It uses all three files most containers
need: `args.json` (how Pantavisor runs it), `config.json` (entrypoint and
environment) and `mdev.json` (which device nodes it gets). It was tested
with the armv8 SDK on an Orange Pi 5B.

The application, `rtc-reader.c`:

```c
#include <errno.h>
#include <fcntl.h>
#include <linux/rtc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

int main(void)
{
	const char *dev = getenv("RTC_DEV");
	const char *interval = getenv("RTC_INTERVAL");
	int secs = interval ? atoi(interval) : 10;

	if (!dev)
		dev = "/dev/rtc0";
	if (secs <= 0)
		secs = 10;

	for (;;) {
		struct rtc_time tm;
		int fd = open(dev, O_RDONLY);

		if (fd < 0) {
			printf("rtc-reader: open %s: %s\n", dev, strerror(errno));
		} else if (ioctl(fd, RTC_RD_TIME, &tm) < 0) {
			printf("rtc-reader: RTC_RD_TIME on %s: %s\n", dev, strerror(errno));
		} else {
			time_t now = time(NULL);
			struct tm sys;

			gmtime_r(&now, &sys);
			printf("rtc-reader: %s %04d-%02d-%02d %02d:%02d:%02d UTC, system %04d-%02d-%02d %02d:%02d:%02d UTC\n",
			       dev, tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
			       tm.tm_hour, tm.tm_min, tm.tm_sec,
			       sys.tm_year + 1900, sys.tm_mon + 1, sys.tm_mday,
			       sys.tm_hour, sys.tm_min, sys.tm_sec);
		}
		if (fd >= 0)
			close(fd);
		fflush(stdout);
		sleep(secs);
	}
}
```

It never exits: if the RTC is missing it logs the error and retries, so the
container log says what is wrong instead of the container restarting.

`args.json` restarts only this container if it fails, counts it as up once
it has started, and has Pantavisor load the `rtc` driver before starting it:

```json
{
    "PV_RESTART_POLICY": "container",
    "PV_STATUS_GOAL": "STARTED",
    "PV_DRIVERS_REQUIRED": [
        "rtc"
    ]
}
```

`config.json` sets the entrypoint and the environment the application reads:

```json
{
    "Entrypoint": ["/usr/bin/rtc-reader"],
    "Env": [
        "RTC_DEV=/dev/rtc0",
        "RTC_INTERVAL=10"
    ],
    "WorkingDir": "/"
}
```

`mdev.json` gives the container the RTC, read-only, plus the basic nodes
(busybox mdev rules: `<regex> <uid>:<gid> <mode>`):

```json
{
    "rules": [
        "rtc[0-9]* 0:0 444",
        "null 0:0 666",
        "zero 0:0 666",
        "u?random 0:0 444"
    ]
}
```

Build and pack it:

```bash
. ~/pv-sdk-armv8/environment-setup-*
mkdir -p rootfs/usr/bin
$CC -Wall -Werror -o rootfs/usr/bin/rtc-reader rtc-reader.c
pv-mkpvrexport --base \
    --args-json args.json \
    --config-json config.json \
    --mdev-json mdev.json \
    rootfs pv-rtc
```

Deploy `pv-rtc.pvrexport.tgz` as in [Deploy it](#deploy-it). The container's
console log (source `/lxc/console.log`, platform `pv-rtc` in the device's
Pantahub logs) then shows:

```
rtc-reader: /dev/rtc0 2026-10-14 21:35:31 UTC, system 2026-10-14 21:35:30 UTC
```

### The RTC driver

`PV_DRIVERS_REQUIRED` names a driver alias from the BSP's `bsp/drivers.json`.
Pantavisor loads the alias's modules before starting the container. If the
board's RTC driver is built into the kernel, drop `PV_DRIVERS_REQUIRED` from
`args.json`. If it is a module, the BSP must define the alias, e.g. for the
Orange Pi 5B's HYM8563:

```json
{
    "#spec": "driver-aliases@1",
    "all": {
        "rtc": [
            "rtc_hym8563"
        ]
    }
}
```

In a BSP built with this layer, set it in the machine configuration;
`pantavisor-bsp` merges it into `bsp/drivers.json`:

```bitbake
PV_BSP_DRIVERS = '{"all": {"rtc": ["rtc_hym8563"]}}'
```

If the driver is not loaded, the container still starts and logs
`open /dev/rtc0: No such file or directory`.
