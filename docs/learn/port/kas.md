+++
title = "Building"
weight = 4

# SEO Configuration
description = "Learn how to build Pantavisor Linux images using Kas. Complete guide to the build system, configuration, and compilation."
keywords = ["pantavisor build", "kas build system", "yocto build", "embedded linux build", "pantavisor compilation", "device image build", "pantavisor kas", "build configuration", "embedded development", "iot build system"]
meta_description = "Building Pantavisor Linux: Guide to building device images using the Kas build system for Pantavisor Linux."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Building Pantavisor Linux Images"
og_description = "Learn how to build Pantavisor Linux images using the Kas build system. Complete build and configuration guide."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Building Pantavisor Linux Images"
twitter_description = "Learn how to build Pantavisor Linux images using the Kas build system"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.8
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/port/kas/"
+++


### Running the Build

Once you have saved your changes to the `Kconfig` file, you can launch the interactive build menu.

From the root of your `meta-pantavisor` directory, run:

```bash
kas menu
```

This command opens the Kconfig menu interface. You will need to select the components for your build.

1. **Select Build Type**: Choose `singleconfig`.

2. **Select Codename**: Select the Yocto branch you are targeting. For our example, this is scarthgap.

3. **Select Build Target**: This defines the type of Pantavisor image to build.

- `pantavisor-remix`: Allows you to customize and select which containers will be pre-installed on the image.

- `pantavisor-starter`: A pre-configured image that includes a base set of containers for network, Wi-Fi, and the `pvr-sdk`.

For this example, let's select `pantavisor-starter`.

4. **Select Machine**: Navigate to the "Machine" menu and select your target. You should now see verdin-imx8mm in the list.

After making your selections, you can exit the menu. You will be prompted to save the configuration and can then choose to start the build process immediately.

### Flashing the Image

When the build is finished, you can find the flashable images in the output directory.

**Image Location**: `build/tmp-scarthgap/deploy/images/verdin-imx8mm/`

(Note: The path contains your selected codename (`scarthgap`) and machine name (`verdin-imx8mm`)).

### Understanding the Output Directory

In this directory, you will find many files. This is the standard output from a Yocto build. The most important files typically include:

- `.wic.bz2` / `.wic.gz`: A compressed, "writeable image" file. This is usually the final, flashable image for SD cards or eMMC.

- **Root Filesystem** (`.tar.gz`, `.ext4`, etc.): The raw root filesystem, often used for other deployment methods.

- **Kernel Image**: (`zImage`, `bzImage`, `fitImage`, etc.) The compiled Linux kernel.

- **Device Tree Blobs** (`.dtb`): Hardware configuration files for the kernel.

- **Bootloader Files**: (`u-boot.img`, etc.)

- **Manifest Files** (`.manifest`): A text file listing every package and version installed in the image.

### Flashing with bmaptool

For most boards that boot from an SD card, the easiest way to flash the image is with `bmaptool`. It's a tool that intelligently copies large sparse files (like `.wic` images) much faster than traditional tools like `dd`.

1. **Identify the Image**: For our example, the file will be named something like `pantavisor-starter-verdin-imx8mm.wic.bz2`.

2. **Find Your Target Device**: Insert your SD card and find its device name. You can use a command like `lsblk` to list block devices. It will likely be `/dev/sdX` (e.g., `/dev/sdb`, `/dev/sdc`).

> **Warning**: Be absolutely certain you have the correct device name. Flashing to the wrong device (like your computer's main drive) will destroy all data on it.

3. **Flash the Image**: Run the `bmaptool` command. It will decompress the image on the fly.


```bash
# Replace 'pantavisor-starter-...' with your image name
# Replace '/dev/sdX' with your target device

bmaptool copy pantavisor-starter-verdin-imx8mm.wic.bz2 /dev/sdX
```

### Important Flashing Note

The method for flashing an image varies greatly between devices.

Some targets (like the Raspberry Pi) are flashed using an SD card.

Other targets (like many Toradex or Variscite boards) may require a special utility or process to flash the image onto internal eMMC or raw NAND memory.

Always refer to the manufacturer's documentation for the correct flashing procedure for your specific board.

For instructions on targets officially supported by `meta-pantavisor`, you can also check the [Pantavisor documentation](https://docs.pantahub.com/).
