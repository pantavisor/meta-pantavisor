+++
title = "Device specification"
weight = 3

# SEO Configuration
description = "Learn about device machine specifications for porting Pantavisor Linux. Guide to hardware configuration and board support packages."
keywords = ["pantavisor machine", "device specification", "board support", "hardware configuration", "pantavisor porting", "machine config", "embedded hardware", "bsp configuration", "device porting", "yocto machine"]
meta_description = "Device Specification: Guide to machine configurations and hardware specifications for porting Pantavisor Linux to new devices."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Pantavisor - Device Specification"
og_description = "Learn about device machine specifications for porting Pantavisor Linux to new hardware platforms."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Pantavisor Device Specification"
twitter_description = "Guide to machine specifications for porting Pantavisor Linux to new devices"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.8
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/port/machine/"
+++

## How to Add a New `kas` Machine to `meta-pantavisor`

After defining a `kas` platform, the next step is to create a **machine** file. This file is the most specific configuration, connecting the general platform (which contains all the layers) to a single, specific device.

This file tells `kas` two primary things:
1.  Which platform (and all its layers) to use.
2.  What to set the Yocto `MACHINE` variable to.

> **Before You Start:** We already have many machines defined in `meta-pantavisor`. Before creating a new one, please check if a file for your device already exists:
>
> * [**View Existing Machines**](https://github.com/pantavisor/meta-pantavisor/tree/master/kas/machines)


### Example: Adding the Verdin i.MX 8MM machine

Let's continue our example by creating a machine file for the **Verdin i.MX 8M Mini**, which uses the `toradex-nxp` platform we defined in the previous tutorial.

#### 1. Find the Official Machine Name

Before creating the file, you must find the exact `machine` name defined by the vendor's BSP. This name typically corresponds to a `.conf` file in the vendor's Yocto layer.

For example, in the Toradex BSP layers (like `meta-toradex-nxp`), you can find machine configurations under `conf/machine/`. The file we are looking for is `verdin-imx8mm.conf`.

Therefore, the machine name is: **`verdin-imx8mm`**

#### 2. Create the Machine YAML File

Now, we create a new file in the `kas/machines/` directory, named after our machine: `verdin-imx8mm.yaml`.

This file will be very simple. Its main jobs are to include the correct platform and state the machine name.

Add the following content to `kas/machines/verdin-imx8mm.yaml`:

```yaml
header:
  version: 16
  includes:
    # 1. Include the platform we created in the previous tutorial
    - kas/platforms/toradex-nxp.yaml

# 2. Specify the exact machine name from the BSP layer
machine: "verdin-imx8mm"
```