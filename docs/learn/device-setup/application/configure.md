+++
title = "Configure Application Settings"
weight = 43

# SEO Configuration
description = "Configure application settings on Pantavisor Linux. Learn to edit manifests, set environment variables, and manage app configurations."
keywords = ["configure pantavisor apps", "app configuration", "application manifest", "environment variables", "app settings", "container config", "pantavisor configuration", "app customization", "embedded app config", "application management"]
meta_description = "Configure Application Settings: Complete guide to customizing app configurations on Pantavisor Linux. Edit manifests, set variables, and manage settings."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Configure Application Settings on Pantavisor Linux"
og_description = "Learn to configure and customize application settings on your Pantavisor Linux device. Complete guide to app configuration management."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Configure Pantavisor Applications"
twitter_description = "Customize application settings and configurations on your containerized embedded Linux device"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.7
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/device-setup/configure-applications/"
+++

Let's now modify files and configurations within a container running on a Pantavisor-managed device.

Because each container's root filesystem (**rootfs**) is a read-only **SquashFS** image, you cannot directly edit files on a running device. Instead, Pantavisor uses an overlay system. You make changes in a local copy of your device's configuration repository, and then you "post" a new revision to the device. The `_config/<container-name>/` directory in your repository serves as a staging area for these overlays.

***

### Step 1: Clone the Device Repository

First, clone the device's current state to your local machine using the `pvr clone` command. This will create a directory containing your device's configuration.

```bash
pvr clone <device_ip> my-device
cd my-device
```

### Step 2: Make Your Changes

All file modifications (adding, editing, or removing) for a specific container must be made within the `_config/<container-name>/` directory. The directory structure you create here will be overlaid onto the container's rootfs.

**Example A: Edit a Configuration File**

Let's change the default port for the embedded web server in the pvr-sdk container from 12368 to 12369.

Open the configuration file located at `_config/pvr-sdk/etc/pvr-sdk/config.json`.

Change the port value to `"12369"`.

The updated file should look like this:

```bash
{
    "httpd": {
        "listen": "0.0.0.0",
        "port": "12369"
    }
}
```

**Example B: Add a New File**

Now, let's add your public SSH key to the container to enable passwordless login.

Create the necessary directory structure. If the directories don't exist, create them:

```bash
mkdir -p _config/pvr-sdk/home/root/.ssh
```

Append your public key to the authorized_keys file:

```bash
cat ~/.ssh/id_rsa.pub >> _config/pvr-sdk/home/root/.ssh/authorized_keys
```

Note: Replace id_rsa.pub with the name of your public key file if it's different.

### Step 3: Stage and Commit Changes

Now that you've made your changes, you need to commit them to your local repository.

Check the status of your repository. This shows which files have been modified or added.

```bash
pvr status
```

The output will look similar to this, showing one modified (C) file and one untracked (?) file:

```bash
C _config/pvr-sdk/etc/pvr-sdk/config.json
? _config/pvr-sdk/home/root/.ssh/authorized_keys
```

Add (stage) your changes to be included in the next commit.

```bash
pvr add .
```

Check the status again. The files are now staged for the commit (A means added).

```bash
pvr status

A _config/pvr-sdk/home/root/.ssh/authorized_keys
C _config/pvr-sdk/etc/pvr-sdk/config.json
```

**Update Container Signature**: If the container you modified is digitally signed (like pvr-sdk), you must update its signature to reflect the changes. This ensures the integrity of the container.

```bash
pvr sig update
pvr add .

pvr commit -m "Change web server port and add SSH key for pvr-sdk"
```

## Step 4: Deploy to the Device

Post the new revision to your device. Pantavisor will automatically apply the update, which typically involves a system reboot.

```bash
pvr post
```

Upon receiving the new revision, the device will apply the changes and restart.

## Step 5: Verify the Changes

After the device reboots, you can verify that your changes were applied successfully.

Test your SSH access:

```bash
ssh root@<device_ip>
```

Check the web UI by navigating to the new port in your browser: `http://<device_ip>:12369/app`