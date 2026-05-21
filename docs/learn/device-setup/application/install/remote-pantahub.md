+++
title = "Pantahub"
weight = 43

# SEO Configuration
description = "Install your first application on Pantavisor Linux using Pantacor Hub. Step-by-step guide to install Home Assistant from the marketplace."
keywords = ["install pantavisor app", "home assistant install", "pantacor hub installation", "first application", "pantacor marketplace", "container install", "app installation guide", "embedded app install", "pantavisor applications", "iot app deployment"]
meta_description = "Install Your First Application: Complete guide to installing Home Assistant and other apps on Pantavisor Linux using Pantacor Hub."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Install Your First Application on Pantavisor Linux"
og_description = "Learn to install applications like Home Assistant on your Pantavisor Linux device using Pantacor Hub."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Install Apps on Pantavisor Linux"
twitter_description = "Step-by-step guide to installing your first application on embedded Linux with containers"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.8
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/device-setup/install-first-application/"
+++

This guide explains how to install an application on your device using the Pantahub web interface.

## 1. Claim Your Device

Before you can manage a device, you must first claim it in your Pantahub account. Claiming associates the physical device with your account, allowing you to manage it remotely.

To do this, you'll need the device's unique Device ID and Challenge token. The easiest way to retrieve these is directly from the device's serial console.

Connect to your device's serial console.

Run the following commands to display the required values:

```bash
# Get the challenge token
cat /pv/challenge
pleasantly-finer-unicorn

# Get the device ID
cat /pv/device-id
5b582638c67920b9de2
```

Log in to your account at `hub.pantacor.com` and navigate to the Claim Devices page.

Enter the `device-id` and `challenge` you just retrieved to claim the device.

Once claimed, your device will appear in your device list. For more detailed information on claiming, please refer to the official documentation.

## 2. Deploy an Application

With the device successfully claimed, you can now deploy a new application.

From your device list, click on the device name to open its dashboard.

Navigate to the Manage tab.

Click the Begin Transaction button. A transaction is a set of changes that will be applied to your device.

To add your application, click Upload New Part.

Select and upload your application's container file, use the `helloworld.tar.gz` created with `pvr` in this [section](local-pvtx).

Once the file is uploaded, add a commit message describing your changes and click Commit Transaction.

## 3. Monitor the Update

After you commit the transaction, Pantahub will automatically push the update to your device. You can monitor the deployment progress in real-time from the device dashboard.

The device will download the update, reboot, and apply the new revision. When the process is complete, the new revision will be marked as `DONE` in the dashboard, confirming your application was successfully installed.