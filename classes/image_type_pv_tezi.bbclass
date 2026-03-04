inherit image_type_tezi

IMAGE_TYPEDEP:pv_teziimg = "tar.xz"
do_image_pv_teziimg[vardepsexclude] += "TEZI_ARTIFACTS"

WKS_FILE_DEPENDS:append = " pantavisor-tezi-metadata"

python tezi_pv_artifacts() {
    import json
    import time
    import os
    import glob

    image_link  = d.getVar('IMAGE_LINK_NAME')
    machine     = d.getVar('MACHINE')
    deploy_dir  = d.getVar('DEPLOY_DIR_IMAGE')
    workdir     = d.getVar('WORKDIR')
    pn          = d.getVar('PN')
    image_ver   = d.getVar('PV')
    release_dt  = time.strftime('%Y-%m-%d')

    complete_dir = os.path.join(workdir, f"deploy-{pn}-image-complete")
    rootfs_path  = os.path.join(complete_dir, f"{image_link}.tar.xz")

    uenv_path   = os.path.join(deploy_dir, "u-boot-initial-env")
    uenv_file   = os.path.basename(uenv_path) if os.path.exists(uenv_path) else ""

    flash_type = d.getVar('TORADEX_FLASH_TYPE') or "emmc"
    uboot_file = f"u-boot-nand-{machine}.imx" if flash_type == "rawnand" else f"u-boot-{machine}.bin"
    uboot_path  = os.path.join(deploy_dir, uboot_file)

    image_json = {
        "config_format": 2,
        "autoinstall": True,
        "name": f"Pantavisor TEZI base installer for {machine}",
        "description": "Pantavisor TEZI base image for Pantahub",
        "version": image_ver,
        "release_date": release_dt,
        "u_boot_env": uenv_file,
        "prepare_script": "prepare.sh",
        "wrapup_script": "wrapup.sh",
        "marketing": "marketing.tar",
        "icon": "pantacor.png",
        "supported_product_ids": ["0044", "0040", "0045", "0036"],
    }

    if flash_type == "rawnand":
        image_json["mtddevs"] = [
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

        if os.path.exists(rootfs_path):
            image_json["mtddevs"][1]["ubivolumes"].append({
                "content": {
                    "filesystem_type": "ubifs",
                    "uncompressed_size": os.path.getsize(rootfs_path),
                    "filename": "rootfs.tar.xz"
                },
                "name": "pvboot"
            })
    else:
        image_json["rawfiles"] = []
        if os.path.exists(rootfs_path):
            image_json["rawfiles"].append({
                "filename": os.path.basename(rootfs_path),
                "name": "rootfs",
                "content": {
                    "filesystem_type": "ext4",
                    "uncompressed_size": os.path.getsize(rootfs_path)
                }
            })

    image_json_path = os.path.join(deploy_dir, "image.json")
    with open(image_json_path, 'w') as f:
        json.dump(image_json, f, indent=4)

    tezi_meta_work = os.path.join(workdir, "tezi-metadata", "deploy")
    if os.path.exists(tezi_meta_work):
        for f in os.listdir(tezi_meta_work):
            src = os.path.join(tezi_meta_work, f)
            dst = os.path.join(deploy_dir, f)
            if os.path.isfile(src) and not os.path.exists(dst):
                import shutil
                shutil.copy2(src, dst)

    artifacts = []
    for fname in ["prepare.sh", "wrapup.sh", "pantacor.png",
                  "marketing.tar", uenv_file, "image.json"]:
        full = os.path.join(deploy_dir, fname)
        if os.path.exists(full):
            artifacts.append(full)

    if flash_type == "rawnand":
        if os.path.exists(uboot_path):
            artifacts.append(uboot_path)
        elif fname.startswith("u-boot-nand"):
            matches = glob.glob(os.path.join(deploy_dir, f"u-boot-nand*{machine}*.imx"))
            if matches:
                artifacts.append(matches[0])

    if os.path.exists(rootfs_path):
        artifacts.append(rootfs_path)

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
        else
            cp -L "$f" "$staging_dir/"
        fi
    done

    tar -cJf ${IMGDEPLOYDIR}/${IMAGE_NAME}.rootfs.pv_teziimg.tar.xz \
        -C "${WORKDIR}/teziimg-staging" ${IMAGE_LINK_NAME}-pv-tezi
}
