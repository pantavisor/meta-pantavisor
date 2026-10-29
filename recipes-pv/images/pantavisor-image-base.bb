SUMMARY = "Pantavisor image base: the generic parts of a flashable image"
DESCRIPTION = "Packs what pantavisor-starter is made of, before any signing \
identity is applied: the BSP export, the core container exports, the boot \
files and the partition layout. 'pvr image assemble' (and the Pantahub \
builder's image builds) turn it into a flashable image for a signing \
identity in minutes: trust and PV_OEM_NAME/PV_POLICY in the initrd, the BSP \
and the containers re-signed, apps and an OEM part added. Supports the \
Raspberry Pi tryboot A/B layout (rpi-tryboot) and U-Boot boards whose \
storage is one ext4 partition holding boot.scr (uboot-gpt)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit deploy nopackages image-artifact-names

PVROOT_CONTAINERS_CORE ?= "pv-pvr-sdk pv-alpine-connman pvwificonnect pv-avahi pv-avahi-browse"

# The partition layout 'pvr image assemble' writes: rpiab (layout version
# 1) for rpi-tryboot machines; a machine opts in to uboot-gpt (version 2).
PV_IMAGE_BASE_LAYOUT ?= "${@bb.utils.contains('PANTAVISOR_FEATURES', 'rpi-tryboot', 'rpiab', '', d)}"
# uboot-gpt: the storage partition's GPT name; the ext4 label is always
# root, which pantavisor mounts (PV_STORAGE_DEVICE=LABEL=root).
PV_IMAGE_BASE_PARTNAME ?= "root"

python __anonymous () {
    layout = d.getVar("PV_IMAGE_BASE_LAYOUT")
    if layout == "rpiab":
        d.setVar("PV_IMAGE_BASE_LAYOUT_VERSION", "1")
        d.appendVarFlag('do_compile', 'depends', ' rpi-bootsel:do_image_complete')
    elif layout == "uboot-gpt":
        d.setVar("PV_IMAGE_BASE_LAYOUT_VERSION", "2")
        d.appendVarFlag('do_compile', 'depends', ' virtual/bootloader:do_deploy')
    else:
        raise bb.parse.SkipRecipe("pantavisor-image-base needs PV_IMAGE_BASE_LAYOUT rpiab (rpi-tryboot) or uboot-gpt")
    for img in d.getVar("PVROOT_CONTAINERS_CORE").split():
        d.appendVarFlag('do_compile', 'depends', ' %s:do_deploy' % img)
}

do_compile[depends] += " \
	pantavisor-bsp:do_compile \
	pantavisor-pvroot:do_deploy \
"
do_compile[cleandirs] = "${B}/base"
do_compile[vardeps] += "PVROOT_CONTAINERS_CORE PV_IMAGE_BASE_LAYOUT PV_IMAGE_BASE_LAYOUT_VERSION PV_IMAGE_BASE_PARTNAME"

do_configure[noexec] = "1"

do_compile() {
	base=${B}/base
	install -d $base/containers

	cp -L ${DEPLOY_DIR_IMAGE}/pantavisor-bsp-${MACHINE}.pvrexport.tgz $base/bsp.pvrexport.tgz
	containers=""
	for img in ${PVROOT_CONTAINERS_CORE}; do
		cp -L ${DEPLOY_DIR_IMAGE}/$img.pvrexport.tgz $base/containers/$img.pvrexport.tgz
		containers="$containers${containers:+, }\"containers/$img.pvrexport.tgz\""
	done
	# pantavisor-pvroot's link name (scarthgap adds IMAGE_NAME_SUFFIX).
	pvroot=${DEPLOY_DIR_IMAGE}/pantavisor-pvroot-${MACHINE}${IMAGE_NAME_SUFFIX}.tar.gz
	[ -e $pvroot ] || pvroot=${DEPLOY_DIR_IMAGE}/pantavisor-pvroot-${MACHINE}.tar.gz
	tar -xzf $pvroot -O ./config/pantahub.config > $base/pantahub.config

	if [ "${PV_IMAGE_BASE_LAYOUT}" = "rpiab" ]; then
		cp -L ${DEPLOY_DIR_IMAGE}/rpi-bootsel.vfat $base/bootsel.vfat
		# rpi-tryboot-ab.wks: boot_a and boot_b take the boot vfat the BSP
		# carries as bsp/pantavisor-rpi.img.gz; its file 'pantavisor' is the
		# initrd holding the trust and pantavisor.config.
		cat > $base/layout.json <<-EOF
			{
			  "version": ${PV_IMAGE_BASE_LAYOUT_VERSION},
			  "machine": "${MACHINE}",
			  "bootloader": "rpiab",
			  "table": "msdos",
			  "align": 4194304,
			  "partitions": [
			    {"name": "bootsel", "fs": "vfat", "size": 33554432, "active": true, "source": "bootsel.vfat"},
			    {"name": "boot_a", "fs": "vfat", "size": 134217728, "source": "bsp:bsp/pantavisor-rpi.img.gz"},
			    {"name": "boot_b", "fs": "vfat", "size": 134217728, "source": "bsp:bsp/pantavisor-rpi.img.gz"},
			    {"name": "root", "fs": "ext4", "label": "root", "source": "pvroot"}
			  ],
			  "initrd": {"bsp": "bsp/pantavisor-rpi.img.gz", "path": "pantavisor"},
			  "containers": [$containers]
			}
		EOF
	else
		# One ext4 partition is the whole storage: U-Boot runs its
		# /boot/boot.scr, which reads /oemEnv.txt and /boot/uboot.txt and
		# boots trails/<rev>/bsp; bsp/pantavisor is the initrd itself.
		cp -L ${DEPLOY_DIR_IMAGE}/boot.scr $base/boot.scr
		cp -L ${DEPLOY_DIR_IMAGE}/oemEnv.txt $base/oemEnv.txt
		cat > $base/layout.json <<-EOF
			{
			  "version": ${PV_IMAGE_BASE_LAYOUT_VERSION},
			  "machine": "${MACHINE}",
			  "bootloader": "uboot",
			  "table": "gpt",
			  "align": 1048576,
			  "partitions": [
			    {"name": "${PV_IMAGE_BASE_PARTNAME}", "fs": "ext4", "label": "root", "source": "pvroot",
			     "files": {"boot/boot.scr": "boot.scr", "oemEnv.txt": "oemEnv.txt"}}
			  ],
			  "initrd": {"bsp": "bsp/pantavisor"},
			  "containers": [$containers]
			}
		EOF
	fi
	tar --owner=0 --group=0 --numeric-owner --sort=name -C $base -cf ${B}/${PN}-${MACHINE}.tar .
}

do_deploy() {
	install -m 0644 ${B}/${PN}-${MACHINE}.tar ${DEPLOYDIR}/
}

addtask deploy after do_compile before do_build
