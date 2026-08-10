# Flashing: Orange Pi i96

**Flash method:** SD card — see [sdcard.md](../sdcard.md)

**Machine:** `orangepi-i96` (KAS machine name `96boards-orangepi-i96`)

The Orange Pi i96 is an RDA8810PL (ARM Cortex-A5) board in the 96Boards IE form
factor. Its BSP lives in a separate layer,
[meta-orangepi-i96](https://github.com/pantavisor/meta-orangepi-i96), which the
KAS config fetches automatically.

## Before you start

**The serial console runs at 921600 baud, not 115200.** This is not a
preference — the boot ROM prints at that rate on this pin, so anything slower
shows garbage for the first half of the boot. Most tools default to 115200 and
will simply show nothing:

```sh
pvr device tty -d /dev/ttyUSB0 -b 921600
```

There is no Ethernet on this board, so WiFi is the only network path.

## Building

```sh
./kas-container build kas/build-configs/release/96boards-orangepi-i96-scarthgap.yaml
```

## Writing the SD card

The build does not emit a ready-to-flash `.img`. The bootloader is a hybrid —
the vendor SPL (DDR and clock init) followed by a modern U-Boot stage-2 — and it
has to be placed at a raw offset ahead of the partition table, which a plain
rootfs image cannot express. Assemble it with:

```sh
DEPLOY=<build>/tmp-scarthgap/deploy/images/orangepi-i96 \
BL=bootloader.rda \
OUT=orangepi-i96.img \
sh recipes-bsp/u-boot/files/mk-sd-image.sh
```

Then write `orangepi-i96.img` to the card with any of the usual tools.

`bootloader.rda` is produced by `package-bootloader.sh` in the BSP layer. A blob
built before the board's pad-map fix boots normally but leaves the board with no
SDIO and therefore no WiFi, which looks exactly like a driver fault — see
section 15 of `MODEM-WIFI-PORT.md` in the BSP layer if you hit that.

## First boot

Boot takes noticeably longer the first time. Pantavisor verifies the SHA-256 of
every object in the trail, and on a single-core Cortex-A5 with nothing cached
that is a few minutes. Later boots skip most of it.

## WiFi

Provision with `pvwificonnect-cli` from the `pvwificonnect` container:

```sh
pventer -c pvwificonnect pvwificonnect-cli connect -s <SSID> -p <PSK>
```

Credentials persist, and the board rejoins the network unattended after a
reboot. Confirm an association with `ifconfig wlan0` showing an `inet addr` —
that is the real check.

The board has no WiFi MAC in NVRAM, so the driver derives a stable one from the
SD card's CID. The address is therefore tied to the card, not the board: moving
the card to another i96 moves the MAC with it. Addresses start with `02:`
(locally administered).

## Known limitations

Two features the hardware advertises do not work, and neither is specific to
Pantavisor — both were reproduced on the vendor's own Debian image using vendor
tools:

- **Bluetooth.** The controller never answers HCI. `hciattach` reports
  `Device setup complete` and then every command times out.
- **WiFi AP / softap.** Every layer reports success — the interface enters AP
  mode with the right SSID — but no beacon is ever transmitted.

Sections 30 and 31 of `MODEM-WIFI-PORT.md` in the BSP layer document both in
full, including the evidence that the driver here is identical to the vendor's
on every relevant line. Please read them before investigating either.

For provisioning a device that has never been configured, use
`pvwificonnect-cli improv-serial`, which needs neither Bluetooth nor an AP.
