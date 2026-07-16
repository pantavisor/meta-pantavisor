---
title: Download and Flash Image
sidebar_position: 1
description: Step-by-step guide to download and flash Pantavisor images to SD cards for Raspberry Pi and embedded devices.
---

This guide will walk you through setting up **Pantavisor** on a **Raspberry Pi 3B**. While Pantavisor supports a variety of embedded devices, the steps here are tailored for the Raspberry Pi 3B. The same principles apply to other boards — see [Install on hardware](/meta-pantavisor/getting-started/how-to-install) for board-specific guides.

## Prerequisites

Before you begin, make sure you have the following ready:

* **Internet connection**: Required to download the necessary files.
* **Laptop or desktop computer**: You'll use this to download the Pantavisor image and flash it onto the microSD card.
* **MicroSD card**: A card with at least **8GB** of storage is recommended.
* **Compatible embedded device**: This guide focuses on the **Raspberry Pi 3B**.
* **SD card reader**: To connect the microSD card to your computer.
* **USB to TTY serial converter**: This is a crucial tool for debugging your device. It allows you to connect to the device's serial console and see boot logs, error messages, and system output directly on your computer.

---
## Download the Pantavisor Image

The first step is to get the Pantavisor image for your specific device.

1.  Head over to our [Downloads page](https://pantavisor.io/downloads/) to see all available platforms and images.
2.  Find the image that matches your device—in this case, select the image for the **Raspberry Pi 3B**. For the Raspberry Pi 3B/3B+/4, choose the **raspberrypi-armv8** image. Download the latest stable version.
3.  The downloaded file will be a compressed image, typically named **`pantavisor-starter-raspberrypi-armv8.rootfs.wic.bz2`**.

> **Compatibility Check**: To avoid issues, always verify that your device is officially supported by Pantavisor before you download and flash the image. You can find a complete list of supported platforms on the [supported hardware page](/meta-pantavisor/overview/supported-device).

---
## Flash the Image to Your MicroSD Card

Now that you have the Pantavisor image, the next step is to write it to your microSD card. We recommend **pvflasher**, Pantavisor's own flashing tool. It natively supports `.wic` and `.bmap` image formats, which means it only writes the blocks that contain data — making it significantly faster than traditional tools like `dd`. It also verifies the written data with checksums automatically.

### Using `pvflasher` (Recommended)

**pvflasher** works on **Linux**, **macOS**, and **Windows**, and offers both a **GUI** and a **CLI**.

1.  **Install pvflasher** with a single command:

    * **Linux / macOS:**
      ```bash
      curl -fsSL https://raw.githubusercontent.com/pantavisor/pvflasher/main/scripts/install.sh | bash
      ```
    * **Windows (PowerShell as Administrator):**
      ```powershell
      powershell -c "irm https://raw.githubusercontent.com/pantavisor/pvflasher/main/scripts/install.ps1 | iex"
      ```

    You can also download pre-built binaries directly from our [Downloads page](https://pantavisor.io/downloads/) or the [pvflasher releases on GitHub](https://github.com/pantavisor/pvflasher/releases).

2.  **List available devices** to find your SD card:

    ```bash
    pvflasher list
    ```

3.  **Flash the image** to your microSD card. Be extremely careful with this step, as entering the wrong device name can overwrite your computer's hard drive.

    ```bash
    # Flash to SD card (replace /dev/sdX with your SD card's device name)
    sudo pvflasher copy pantavisor-starter-raspberrypi-armv8.rootfs.wic.bz2 /dev/sdX
    ```

    pvflasher will automatically detect and use the `.bmap` file if one is present alongside the image, ensuring the fastest possible flash. It also supports compressed images (`.gz`, `.bz2`, `.xz`, `.zst`, `.zip`) without needing to decompress first.

> **Tip**: You can also launch `pvflasher` without arguments to open the **graphical interface**, which lets you browse, download, and flash Pantavisor images — all in one step. Prefer staying in the terminal? `pvflasher install` does the same interactively in your shell — it lists the official release channels (stable, release-candidate) and versions, then downloads and flashes your pick. With it you can skip the manual download step entirely.

---

### Alternative Methods

If you prefer not to use pvflasher, the following tools also work:

#### Using `bmaptool`

1.  Install `bmaptool` on your system:
    * **On Debian/Ubuntu:** `sudo apt-get install bmap-tools`
    * **On Fedora/CentOS:** `sudo dnf install bmap-tools`

2.  Flash the image:

    ```bash
    sudo bmaptool copy pantavisor-starter-raspberrypi-armv8.rootfs.wic.bz2 /dev/sdX
    ```

#### Using `dd`

For advanced users on Linux/macOS:

```bash
# Decompress and flash (replace /dev/sdX with your SD card's device name)
bzcat pantavisor-starter-raspberrypi-armv8.rootfs.wic.bz2 | sudo dd of=/dev/sdX bs=4M status=progress
sync
```

> **Note**: `dd` does not use block maps, so it writes every block and will be slower than pvflasher or bmaptool.

**Finding Your SD Card's Device Name:**

* **Linux:** Use `lsblk` or `fdisk -l` to list all storage devices.
* **macOS:** Use `diskutil list` to see a list of connected disks.
* **Windows:** Use `pvflasher list` or check **Disk Management** for the physical drive number.

---
## Boot Up Your Device

With the image successfully flashed, you are ready to boot your Raspberry Pi for the first time.

1.  **Insert** the microSD card into the slot on your Raspberry Pi.
2.  **Connect** a USB-to-TTL serial adapter to the Pi's console pins (GPIO14 TX → adapter RX, GPIO15 RX → adapter TX, GND → GND, 115200 baud) — see [Serial port access](/meta-pantavisor/getting-started/operate/device-access/serial-port).
3.  **Connect** your device to a network. An ethernet cable is highly recommended for the first boot to ensure a stable connection.
4.  **Plug in** the power supply to turn on the device.
5.  **Next:** go to [Device access](/meta-pantavisor/getting-started/operate/device-access) for first-boot instructions.

## Next Steps

- **Claim your device on Pantahub** for remote management — see [Remote access via Pantahub](/meta-pantavisor/getting-started/operate/device-access/remote-pantahub).
- **Install your first application** with `pvr` — see [Install applications](/meta-pantavisor/getting-started/develop/application/install/).