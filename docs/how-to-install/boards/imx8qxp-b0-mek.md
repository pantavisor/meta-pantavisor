# Flashing: NXP i.MX8QXP MEK

**Flash methods:** pv-flash-bundle / uuu (eMMC) | SD card — see the sections above

**Image artifact:** `pv-flash-bundle-imx8qxp-b0-mek.tar.gz` (eMMC) or
`pantavisor-starter-imx8qxp-b0-mek*.wic` (SD card)

## Hardware overview

The i.MX8QXP MEK (Multisensory Enablement Kit) is NXP's own evaluation board
for the i.MX8QuadXPlus SoC. It has both a microSD slot (`J12`, `USDHC1`) and
an onboard eMMC (`EMMC0`); boot source is selected with the **SW2** DIP
switch on the board.

## SD card boot

SW2 = `ON, ON, OFF, OFF` (positions 1–4) selects SD card boot — this is the
board's default out-of-the-box configuration. Insert the flashed SD card and
power on. See the SD card flashing section above for how to write the
`.wic` image.

## uuu (USB download to eMMC)

### 1. Set boot-mode to Serial Downloader

SW2 also selects Serial Downloader (USB) mode, but the exact switch
positions differ from the table above and aren't reproduced here to avoid
giving you a wrong setting — confirm them against NXP's
**i.MX 8QuadXPlus MEK Board Hardware User's Guide** (or the board's Quick
Start Guide) before changing switches on real hardware.

### 2. Connect USB

Connect a USB cable from the board's USB OTG port to your host PC.

### 3. Flash

Using the self-contained bundle (recommended — no `uuu` install needed):

```bash
tar xzf pv-flash-bundle-imx8qxp-b0-mek.tar.gz
cd pv-flash-bundle-imx8qxp-b0-mek
./flash.sh
```

Or manually, with `uuu` already installed on the host:

```bash
sudo uuu -b emmc_all imx-boot-imx8qxp-b0-mek*.bin pantavisor-starter-imx8qxp-b0-mek*.wic
```

See the [uuu section above](../uuu.md) for full details and troubleshooting.
Unlike the i.MX8M-family boards, i.MX8QXP's ROM uses `SDPS:` ("stream")
serial-download mode rather than plain `SDP:` — `pv-flash-bundle`'s
generated `uuu.auto` already accounts for this; if you use `uuu -b emmc_all`
manually, `uuu` picks the right protocol automatically once it detects the
board.

### 4. Restore boot-mode to eMMC

Set SW2 back to eMMC boot mode (per the Hardware User's Guide) and
power-cycle.

## Notes

- eMMC is `USDHC1` (U-Boot `mmc dev 0`, HS400-capable); the SD slot is
  `USDHC2` (U-Boot `mmc dev 1`, UHS-capable) — the board ships with SD as the
  default boot device (`CONFIG_SYS_MMC_ENV_DEV=1` in the vendor U-Boot
  defconfig).
- This is a bare NXP reference board — no vendor-specific bootcmd hacks are
  needed for UUU flashing, unlike Toradex.
