SUMMARY = "Starter Image for Pantavisor"
LICENSE = "MIT"

inherit image pvroot-image

FILESPATH = "${@base_set_filespath(["${FILE_DIRNAME}/${BP}", \
        "${FILE_DIRNAME}/${BPN}", "${FILE_DIRNAME}/files"], d)}"

PVROOT_CONTAINERS_CORE ?= "pv-pvr-sdk pv-alpine-connman pv-pvwificonnect"

PVROOT_IMAGE_BSP ?= "core-image-minimal"

do_rootfs[depends] += "virtual/bootloader:do_deploy"

do_rootfs_boot_scr(){
	if [ -f "${DEPLOY_DIR_IMAGE}/boot.scr" ]; then
		mkdir -p ${IMAGE_ROOTFS}/boot
		cp -f ${DEPLOY_DIR_IMAGE}/boot.scr ${IMAGE_ROOTFS}/boot/
	fi
}


# Paths relative to the meta-pantavisor layer root, set per-machine in
# kas/machines/<machine>.yaml via local_conf_header.
# PV_FLASH_README      - board/method-specific flashing doc (required)
# PV_FLASH_README_DEPS - space-separated list of method docs to prepend
#                        before PV_FLASH_README (e.g. tezi.md, uuu.md)
# Deployed as: pantavisor.md + deps (in order) + PV_FLASH_README
PV_FLASH_README ??= ""
PV_FLASH_README_DEPS ??= ""

python do_deploy_readme () {
    readme = d.getVar('PV_FLASH_README')
    if not readme:
        return
    import os
    layer_dir = os.path.dirname(os.path.dirname(os.path.dirname(d.getVar('FILE'))))
    deps = (d.getVar('PV_FLASH_README_DEPS') or '').split()
    paths = [os.path.join(layer_dir, 'docs/pantavisor.md')]
    paths += [os.path.join(layer_dir, dep) for dep in deps]
    paths += [os.path.join(layer_dir, readme)]
    dst = os.path.join(d.getVar('DEPLOY_DIR_IMAGE'), 'pantavisor-README.md')
    parts = []
    for path in paths:
        if os.path.exists(path):
            with open(path) as f:
                parts.append(f.read())
        else:
            bb.warn('pantavisor-README: file not found: %s' % path)
    if parts:
        with open(dst, 'w') as f:
            f.write('\n\n---\n\n'.join(parts))
        bb.note('Deployed pantavisor-README.md to %s' % dst)
}

PVROOTFS_POSTPROCESS_COMMAND = "do_rootfs_boot_scr; do_deploy_readme"
