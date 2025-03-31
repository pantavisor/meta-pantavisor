inherit image_types

WKS_FILE_DEPENDS:append = " tezi-metadata"

IMAGE_TYPEDEP:teziimg = "tar.gz"
do_image_teziimg[vardepsexclude] += "TEZI_ARTIFACTS"

addtask do_image_pv_teziimg after do_image_tar before do_image_complete

def get_uncompressed_size(d, file_path):
    import os
    base_name = os.path.basename(file_path)
    path = os.path.join(d.getVar('T'), f"image-size.{base_name}")
    if not os.path.exists(path):
        bb.warn(f"[pv-tezi] {path} not found, returning 0")
        return 0
    with open(path, "r") as f:
        size = f.read().strip()
    try:
        return round(float(size), 0)
    except ValueError:
        bb.warn(f"[pv-tezi] Invalid content in {path}: {size}")
        return 0

python tezi_pv_artifacts() {
    import json
    import shutil
    import time
    import os
    import glob

    image_name = d.getVar('IMAGE_LINK_NAME')
    machine = d.getVar('MACHINE')
    deploy_dir = d.getVar('DEPLOY_DIR_IMAGE')
    workdir = d.getVar('WORKDIR')
    imgdeploydir = d.getVar('IMGDEPLOYDIR')
    image_version = d.getVar('PV')
    release_date = time.strftime('%Y-%m-%d')

    rootfs_name = f"{image_name}.tar.xz"
    rootfs_path = os.path.join(workdir, "deploy-" + d.getVar("PN") + "-image-complete", rootfs_name)

    bootfs_name = f"{image_name}.bootfs.tar.xz"
    bootfs_path = os.path.join(workdir, "deploy-" + d.getVar("PN") + "-image-complete", bootfs_name)


    uenv_path = os.path.join(deploy_dir, "u-boot-initial-env")
    uenv_filename = os.path.basename(uenv_path) if os.path.exists(uenv_path) else ""
    uboot_filename = f"u-boot-nand-{machine}.imx"
    uboot_path = os.path.join(deploy_dir, uboot_filename)

    image_json = {
        "config_format": 2,
        "autoinstall": True,
        "name": f"Pantavisor TEZI base installer for {machine}",
        "description": "Pantavisor TEZI base image for Pantahub",
        "version": image_version,
        "release_date": release_date,
        "u_boot_env": uenv_filename,
        "prepare_script": "prepare.sh",
        "wrapup_script": "wrapup.sh",
        "marketing": "marketing.tar",
        "icon": "pantacor.png",
        "supported_product_ids": ["0044", "0040", "0045", "0036"],
        "mtddevs": [
            {
                "content": {
                    "rawfile": {
                        "filename": os.path.basename(uboot_path),
                        "size": os.path.getsize(uboot_path) if os.path.exists(uboot_path) else 0
                    }
                },
                "name": "u-boot1"
            },
            {
                "content": {
                    "rawfile": {
                        "filename": uboot_filename,
                        "size": os.path.getsize(uboot_path) if os.path.exists(uboot_path) else 0
                    }
                },
                "name": "u-boot2"
            },
            {
                "ubivolumes": [],
                "name": "ubi"
            }
        ]
    }

    if bootfs_path and os.path.exists(bootfs_path):
        image_json["mtddevs"][2]["ubivolumes"].append({
            "size_kib": 16384,
            "content": {
                "filesystem_type": "ubifs",
                "uncompressed_size": os.path.getsize(bootfs_path),
                "filename": os.path.basename(bootfs_path)
            },
            "name": "pvboot"
        })

    image_json["mtddevs"][2]["ubivolumes"].append({
        "content": {
            "filesystem_type": "ubifs",
            "uncompressed_size": os.path.getsize(rootfs_path),
            "filename": os.path.basename(rootfs_path)
        },
        "name": "pvroot"
    })

    image_json_path = os.path.join(deploy_dir, "image.json")
    with open(image_json_path, 'w') as f:
        json.dump(image_json, f, indent=4)

    artifacts = []
    for fname in ["prepare.sh", "wrapup.sh", "pantacor.png", "marketing.tar", uenv_filename, uboot_filename, "image.json"]:
        full = os.path.join(deploy_dir, fname)
        if os.path.exists(full):
            artifacts.append(full)
        elif fname.startswith("u-boot-nand"):
            matches = glob.glob(os.path.join(deploy_dir, f"u-boot-nand*{machine}*.imx"))
            if matches:
                artifacts.append(matches[0])

    if os.path.exists(rootfs_path):
        artifacts.append(rootfs_path)

    if os.path.exists(bootfs_path):
        artifacts.append(bootfs_path)

    d.setVar("TEZI_ARTIFACTS", " ".join(artifacts))
}

do_image_pv_teziimg[prefuncs] += "tezi_pv_artifacts"

IMAGE_CMD:pv_teziimg () {
    bbnote "Creating pv-tezi image tarball..."
    tar --transform='s/.*\///' \
        --transform='s,^,${IMAGE_LINK_NAME}-pv-tezi/,' \
        -chf ${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.PV-Tezi.tar \
        ${TEZI_ARTIFACTS}
}

IMAGE_CMD:teziimg[vardeps] += "TEZI_ARTIFACTS"
