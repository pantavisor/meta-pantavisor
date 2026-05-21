+++
title = "PVTX"
weight = 42

# SEO Configuration
description = "Install your first application on Pantavisor Linux using PVTX. Step-by-step guide to install Home Assistant from the marketplace."
keywords = ["install pantavisor app", "home assistant install", "pvtx installation", "first application", "pantacor marketplace", "container install", "app installation guide", "embedded app install", "pantavisor applications", "iot app deployment"]
meta_description = "Install Your First Application: Complete guide to installing Home Assistant and other apps on Pantavisor Linux using the PVTX interface."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Install Your First Application on Pantavisor Linux"
og_description = "Learn to install applications like Home Assistant on your Pantavisor Linux device using the PVTX interface."
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

To add a new container or app to a Pantavisor-enabled system, you can use the **pvr CLI** in conjunction with the **Pantavisor UI (pvtx)**. This guide demonstrates how to download a Docker container from Docker Hub, prepare it for a Pantavisor device, and then upload it using the local network.

### 1. Prerequisites

You'll need a few things set up on your development machine before you get started:
* **Pantavisor pvr CLI**: This command-line tool is essential for managing Pantavisor-enabled devices and their applications. You can install it with the following command:
  ```bash
  # Install Pantavisor CLI (PVR)
  curl -sL https://gitlab.com/pantacor/pvr/-/raw/master/install.sh | bash
  ```
* **Docker**: You'll also need Docker installed and running on your development machine to pull and manage container images.

### 2. Creating a New Pantavisor App

Here's how to create the app package using the **pvr CLI**:

1.  **Create a working directory** for your new app and navigate into it:
    ```bash
    mkdir device-apps
    cd device-apps
    ```

2.  **Initialize a new Pantavisor project** in this directory:
    ```bash
    pvr init
    ```

3.  **Add your app** from Docker Hub. In this example, we'll use the **'hello-world'** container:
    ```bash
    pvr app add helloworld --from hello-world --platform linux/arm64
    ```
    This command pulls the **'hello-world'** image from Docker Hub and prepares the necessary files for Pantavisor.

4.  **Add the new files** to your project's revision history:
    ```bash
    pvr add .
    ```

5.  **Commit the changes** with a descriptive message:
    ```bash
    pvr commit -m "added helloworld app"
    ```

6.  **Export the app** as a `.tar.gz` file. This file contains the container's filesystem and the default configuration policies:
    ```bash
    pvr export helloworld.tar.gz
    ```
    This command creates a compressed archive named `helloworld.tar.gz`.

### 3. Uploading the App to the Device

Now that you have your app package, you can upload it to your Pantavisor-enabled device using the local network and the **pvtx UI**.

1.  **Access the Pantavisor UI**. Open a web browser and navigate to `http://<DEVICE_IP>:12368/app`, replacing `<DEVICE_IP>` with the actual IP address of your device on the local network. This will bring you to the app management page.

2.  **Begin a transition**. On the web page, click on **"begin transition"**. This initiates the process of updating the device's configuration.

3.  **Upload the `.tar.gz` file**. Simply drag and drop the `helloworld.tar.gz` file you created earlier into the designated upload area.

![transction](/images/pvtx-ui-transaction.png)

4.  **Commit the transaction**. Follow the on-screen prompts to commit the changes. The Pantavisor system will handle the rest. Check the serial console for logs, if a reboot is issue and an a debug shell is running a timeout will start before the reboot. Follow the instructions of the console to reboot the device.

5.  **Verify the update**. You can check the device's status and revision history in the **pvtx UI** to confirm the update has been successfully applied. You can also check the running apps on using the serial console with `lxc-ls`.