# Flashing: Variscite VAR-SOM-MX8M-NANO

**Flash methods:** uuu (eMMC) | SD card — see the sections above

**Image artifact:** `pantavisor-starter-imx8mn-var-som*.wic`

## Hardware overview

The VAR-SOM-MX8M-NANO is based on the NXP i.MX8M Nano SoC. It is typically
used with the **Symphony-Board** carrier board.

## SD card boot

Set the boot-mode switches on the Symphony-Board to select SD boot:

| Switch | SD boot | eMMC boot |
|---|---|---|
| SW4-1 | ON | OFF |
| SW4-2 | ON | OFF |
| SW4-3 | OFF | ON |
| SW4-4 | OFF | OFF |

Insert the flashed SD card and power on. See the SD card flashing section
above for how to write the `.wic` image.

## uuu (USB download to eMMC)

### 1. Set boot-mode to USB download

| Switch | USB download |
|---|---|
| SW4-1 | OFF |
| SW4-2 | OFF |
| SW4-3 | OFF |
| SW4-4 | OFF |

### 2. Connect USB OTG

Connect a USB cable from the board's **USB OTG** port to your host PC.

### 3. Flash

```bash
sudo uuu -b emmc_all \
    imx-boot-imx8mn-var-som*.bin \
    pantavisor-starter-imx8mn-var-som*.wic
```

See the uuu section above for full details and troubleshooting.

### 4. Restore boot-mode to eMMC

Set switches back to eMMC boot mode (table above) and power-cycle.

## Notes

- The Variscite BSP (meta-variscite-bsp) provides additional uuu scripts.
  Consult the [Variscite wiki](https://variwiki.com/index.php?title=VAR-SOM-MX8M-NANO)
  for advanced uuu usage.
- CAAM (Cryptographic Accelerator) is enabled and available for
  dm-crypt/dm-verity operations.
