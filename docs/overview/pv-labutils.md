---
sidebar_position: 18
---
# Lab controller container (pv-labutils)

`pv-labutils` (`recipes-containers/pv-labutils/pv-labutils_1.0.bb`) is a
`container-pvrexport` image that packages board-control tooling for a
Pantacor CI lab — USB and mains power switching, SD muxing, flashing
(`uuu`/`dfu-util`/`fastboot`/`rkdeveloptool`), GPIO-driven reset/recovery
control, serial consoles and `pvr` — into a container built, signed and
versioned by this layer instead of a separate Dockerfile/CI pipeline. It
ports [gitlab.com/pantacor/pv-platforms/labutils](https://gitlab.com/pantacor/pv-platforms/labutils).

Unlike most containers in this layer, `pv-labutils` isn't something a
Pantavisor device runs to do its own job — it runs on a **lab controller**
host (itself a Pantavisor device) that drives *other* devices under test
(DUTs) over USB/serial/GPIO.

## Building

```bash
./kas-container build kas/build-configs/release/rpi-scarthgap.yaml --target pv-labutils
```

Output: `build/tmp-scarthgap/deploy/images/<machine>/pv-labutils.pvrexport.tgz`.
It is not part of `pantavisor-starter` or `pantavisor-appengine-distro`, so a
normal image build does not produce it — build the `pv-labutils` target
explicitly for whichever machine is acting as the lab controller.

## Package split

`packagegroup-pv-labutils.bb` splits the tooling into four subpackages so a
controller that only power-cycles boards need not carry the flashing half:

| Subpackage | Tools | Purpose |
|---|---|---|
| `pv-labutils-flash` | `android-tools` (adb/fastboot), `dfu-util`, `rkdeveloptool`, `usbsdmux`, `usbutils`, `uuu` | Board flashing and USB storage muxing |
| `pv-labutils-power` | `libgpiod-tools`, `uhubctl`, `sispmctl`, `raspi-gpio` (rpi machines only) | Per-port USB/mains power switching and GPIO reset/recovery control |
| `pv-labutils-serial` | `picocom`, `screen` | Serial consoles |
| `pv-labutils-shell` | `bash`, `coreutils`, `cronie`, `curl`, `expect`, `git`, `iproute2`, `iputils-ping`, `jq`, `openssh-scp`/`sftp`/`ssh`, `pvr`, `python3` (+`pip`/`requests`), `rsync`, `sed`, `socat`, `sudo`, `tar`, `util-linux`, `vim`, `xz` | Shell, scripting and Pantavisor tooling |

`util-linux`'s default `RRECOMMENDS` pulls its full suite of ~100 subpackages
(`mount`, `lsblk`, `fdisk`, `hwclock`, `uuidgen`, …), not just a minimal core.

`pvcontrol` and `JSON.sh` are not listed anywhere above — they arrive via
`container-pvrexport` + `pantavisor-pvcontrol` automatically, like every
other Pantavisor container.

A lab controller that needs to compile in place (e.g. a CI job building a
native tool) is not covered by the packagegroup — add a build toolchain to
the image recipe explicitly rather than carrying it in every build:

```bitbake
IMAGE_INSTALL:append = " packagegroup-core-buildessential cmake openssl-dev"
```

## GPIO: reset/recovery control

`pv-labutils-power` carries `libgpiod-tools`
(`gpioset`/`gpioget`/`gpioinfo`/`gpiodetect`/`gpiomon`) for driving a DUT's
reset/recovery pins from the lab controller.

The layer also ships a wrapper script, installed to `/usr/bin/pv-gpio-set`:

```bash
pv-gpio-set <chip> <line> <high|low|1|0>
```

For example, to pulse a DUT's reset line low and back high on `gpiochip0`
line 17:

```bash
pv-gpio-set gpiochip0 17 low
sleep 1
pv-gpio-set gpiochip0 17 high
```

It wraps `gpioset`'s v2 CLI (`gpioset -c <chip> <line>=<value>`) so a lab
script doesn't need to know that syntax.

On Raspberry Pi machines (any machine with `rpi` in `MACHINEOVERRIDES`),
`pv-labutils-power` also carries `raspi-gpio`, which prints the 40-pin
header's BCM/physical pin mapping:

```bash
raspi-gpio funcs
```

## Device access (mdev)

Every Pantavisor container already gets `lxc.cgroup.devices.allow = a`; the
rest of the device-access story is `PVRIMAGE_AUTO_MDEV`/an explicit
`mdev.json`, which controls what shows up under `/dev` inside the container.
`pv-labutils` ships an explicit rule file,
`recipes-containers/pv-labutils/files/pv-labutils.mdev.json`, wired in via
`SRC_URI` as `${PN}.mdev.json` (`container-pvrexport` prefers this over the
`PVRIMAGE_AUTO_MDEV` auto-generated default when present):

```json
{
    "rules": [
        ".* 0:0 666"
    ]
}
```

That single permissive rule is enough to reach USB hubs, SD muxes,
DFU/fastboot endpoints, GPIO chips and tty devices — the entire point of
this container.

### Persistent naming for a specific DUT's serial port

USB-serial device numbering (`/dev/ttyUSB0`, `ttyUSB1`, …) is assigned by
the kernel in enumeration order, not by mdev — a rule can't pin a specific
adapter to a fixed number. What it *can* do is create a symlink that always
points at whichever number the kernel gave the adapter in a specific
physical USB port, using the `DEVPATH` uevent variable (the sysfs path,
which encodes the port topology and stays fixed as long as the adapter
stays in that port):

```bash
# find the port path for the adapter currently on ttyUSB0
readlink -f /sys/class/tty/ttyUSB0
# .../usb1/1-1/1-1.3/1-1.3:1.0/ttyUSB0/tty/ttyUSB0
```

Add a rule matching that path ahead of the catch-all in
`pv-labutils.mdev.json` — mdev stops at the first match unless a rule starts
with `-`, so order matters:

```json
{
    "rules": [
        "DEVPATH=.*1-1\\.3.*;ttyUSB[0-9]+ 0:0 0660 >ttyDUT-reset",
        ".* 0:0 666"
    ]
}
```

`DEVPATH=<regex>;` is an extra AND-ed condition (substring match against the
uevent's `$DEVPATH`); `ttyUSB[0-9]+` is the actual devname regex; `>alias`
adds a symlink (`/dev/ttyDUT-reset` alongside `/dev/ttyUSBx`) — use `=alias`
instead to rename the node rather than symlink it. Repeat per DUT position
on the rack with a different port substring/alias.

## Container runtime

`pv-labutils` inherits `core-image` rather than plain `image`: labutils ran
OpenRC as its Docker `init`, and `packagegroup-core-boot`'s sysvinit is the
equivalent that exists in this distro, with `Entrypoint=/sbin/init`.
`IMAGE_INSTALL` is set outright rather than appended to `core-image`'s
default, which also carries `packagegroup-base-extended` — on a board
machine that drags `MACHINE_EXTRA_RRECOMMENDS` (Wi-Fi/BT firmware, kernel
modules) into the container.

There is no syslog daemon: rsyslog `RCONFLICTS busybox-syslog`, which this
distro's busybox `RPROVIDES` as a stub (`trim.cfg` removes the real syslogd
applet), so no syslog daemon can exist here at all. The lab tools write to
stdout, which Pantavisor already captures into `pvcontrol logs`.

`/var` and `/tmp` are permanent overlays (sysvinit needs `/var/run` and
`/var/lock` writable), and the container runs in the `platform` group.

## Deliberately out of scope

- **GitLab runner, Go toolchain, JFrog CLI** — runner concerns; kept on the
  original Docker image until a `gitlab-runner` recipe lands.
- **`yq`, `python3-dotenv`** — no recipe in meta-oe/meta-python scarthgap.
- **`pvflasher`** — blocked upstream: its `main.go` hard-imports the Fyne GUI
  with no build tag, and there are no vendored deps to build it offline.

## Related

- [Container Development](container-development.md) — authoring and packaging containers
- [USB factory-flash bundle](pv-flash-bundle.md) — the other lab/factory tooling recipe in this layer, for flashing a device over USB rather than driving it from a lab rig
- [Manifest Audit](manifest-audit.md) — auditing rootfs content, if extending `pv-labutils`' package set
