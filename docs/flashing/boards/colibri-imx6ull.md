# Flashing: Toradex Colibri iMX6ULL

**Flash method:** Toradex Easy Installer (Tezi) — see the Tezi section above

**Image artifact:** `pantavisor-starter-colibri-imx6ull*pv_teziimg.tar.xz`

## Supported carrier boards

Standard Toradex carrier boards:

- Colibri Evaluation Board (EVB)
- Aster carrier board
- Viola carrier board

## Entering Tezi recovery mode

### Colibri EVB

1. Short the **BOOT_CFG** jumper (JP1) on the EVB to force USB serial download
   mode — consult the EVB schematic for the exact jumper location.
2. Connect a USB Micro-B cable from the EVB's USB OTG port to your host PC.
3. Power on the EVB.
4. Tezi on the host should detect the module automatically.

### Other carrier boards

Refer to the carrier board datasheet for the correct boot-mode configuration.
The general principle is the same: force the i.MX6ULL into USB serial download
mode by pulling `BOOT_MODE[1:0]` to `10b`.

## Flashing

Follow the Tezi flashing procedure described in the section above.

## Notes

- The Colibri iMX6ULL module uses eMMC as its primary storage. Tezi writes
  directly to eMMC; no SD card is needed.
- After flashing, remove the boot-mode jumper before the next power cycle so
  the module boots from eMMC.
