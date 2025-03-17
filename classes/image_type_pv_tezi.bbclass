inherit image_types

IMAGE_TYPEDEP:pv_teziimg = "tar.xz"
do_image_pv_teziimg[vardepsexclude] += "TEZI_ARTIFACTS"

python do_image_bootfs() {
    import os
    import tarfile
    import shutil

    deploy_dir_image = d.getVar('DEPLOY_DIR_IMAGE')
    workdir = d.getVar('WORKDIR')
    image_name = d.getVar('IMAGE_NAME')
    image_link_name = d.getVar('IMAGE_LINK_NAME')
    machine = d.getVar('MACHINE')
    pn = d.getVar('PN')

    boot_scr_file = f"boot.scr-{machine}"
    boot_scr_path = os.path.join(deploy_dir_image, boot_scr_file)

    if not os.path.exists(boot_scr_path):
        bb.fatal(f"[BOOTFS] Boot script not found: {boot_scr_path}")

    intermediate_dir = os.path.join(workdir, f"deploy-{pn}-image-complete")
    os.makedirs(intermediate_dir, exist_ok=True)
    bootfs_output_path = os.path.join(intermediate_dir, f"{image_name}.bootfs.tar.xz")

    with tarfile.open(bootfs_output_path, "w:xz") as tar:
        tar.add(boot_scr_path, arcname="boot.scr")

    deploy_copy_path = os.path.join(deploy_dir_image, f"{image_name}.bootfs.tar.xz")
    shutil.copy2(bootfs_output_path, deploy_copy_path)

    final_named_path = os.path.join(deploy_dir_image, f"{image_link_name}.bootfs.tar.xz")
    shutil.copy2(deploy_copy_path, final_named_path)

    d.setVar("BOOTFS_TARXZ", bootfs_output_path)
}

addtask do_image_bootfs after do_image before do_image_teziimg

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
    pn = d.getVar("PN")
    image_version = d.getVar('PV')
    release_date = time.strftime('%Y-%m-%d')

    complete_dir = os.path.join(workdir, f"deploy-{pn}-image-complete")
    rootfs_path = os.path.join(complete_dir, f"{image_name}.tar.xz")
    bootfs_path = os.path.join(deploy_dir, f"{image_name}.bootfs.tar.xz")

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
                "ubivolumes": [],
                "name": "ubi"
            }
        ]
    }

    if os.path.exists(bootfs_path):
        image_json["mtddevs"][1]["ubivolumes"].append({
            "size_kib": 16384,
            "content": {
                "filesystem_type": "ubifs",
                "uncompressed_size": os.path.getsize(bootfs_path),
                "filename": "bootfs.tar.xz"
            },
            "name": "pvboot"
        })

    if os.path.exists(rootfs_path):
        image_json["mtddevs"][1]["ubivolumes"].append({
            "content": {
                "filesystem_type": "ubifs",
                "uncompressed_size": os.path.getsize(rootfs_path),
                "filename": "rootfs.tar.xz"
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
    bbnote "Creating pv-tezi image tarball (.tar.xz)..."

    staging_dir="${WORKDIR}/teziimg-staging/${IMAGE_LINK_NAME}-pv-tezi"
    mkdir -p "$staging_dir"

    for f in ${TEZI_ARTIFACTS}; do
        bbnote "Staging artifact: $f"
        base=$(basename "$f")

        if echo "$base" | grep -qE '\.rootfs\.tar\.xz$'; then
            cp -L "$f" "$staging_dir/rootfs.tar.xz"
        elif echo "$base" | grep -qE '\.bootfs\.tar\.xz$'; then
            cp -L "$f" "$staging_dir/bootfs.tar.xz"
        elif [ "$base" = "rootfs.tar.xz" ] || [ "$base" = "bootfs.tar.xz" ]; then
            :
        else
            cp -L "$f" "$staging_dir/"
        fi
    done

    tar -cJf ${IMGDEPLOYDIR}/${IMAGE_NAME}.rootfs.pv_teziimg.tar.xz \
        -C "${WORKDIR}/teziimg-staging" ${IMAGE_LINK_NAME}-pv-tezi
}
