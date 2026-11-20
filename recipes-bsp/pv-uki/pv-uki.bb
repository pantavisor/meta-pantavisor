SUMMARY = "Pantavisor unified kernel image (UKI)"
DESCRIPTION = "Bundles the kernel, the pantavisor initramfs and the kernel \
command line into one EFI binary for systemd-boot, and deploys the \
loader.conf that boots it."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

require conf/image-uefi.conf
inherit deploy python3native

SRC_URI = "file://loader.conf"
S = "${WORKDIR}"

INHIBIT_DEFAULT_DEPS = "1"
DEPENDS = " \
	systemd-boot-native \
	python3-pefile-native \
"
PACKAGE_ARCH = "${MACHINE_ARCH}"

INITRAMFS_IMAGE ?= "pantavisor-initramfs"
INITRAMFS_IMAGE_NAME ?= "${INITRAMFS_IMAGE}-${MACHINE}"
INITRAMFS_MULTICONFIG ?= ""
INITRAMFS_DEPLOY_DIR_IMAGE = '${@oe.utils.conditional("INITRAMFS_MULTICONFIG", "", "${DEPLOY_DIR_IMAGE}", "${TOPDIR}/tmp-${DISTRO_CODENAME}-${INITRAMFS_MULTICONFIG}/deploy/images/${MACHINE}", d)}'

# The same image serves every revision: the sdboot backend reads the booted
# revision from systemd-boot's LoaderEntrySelected, and pv_rev=0 is only the
# fallback when that variable is missing.
PV_UKI_CMDLINE ?= "panic=2 root=/dev/ram rootfstype=ramfs rdinit=/usr/bin/pantavisor pv_rev=0 pv_quickboot"
PV_UKI_CMDLINE_MACHINE ??= ""
PV_BOOT_OEMARGS ??= ""

do_compile[depends] += " \
	virtual/kernel:do_deploy \
	systemd-boot:do_deploy \
	${@oe.utils.conditional('INITRAMFS_MULTICONFIG', '', '${INITRAMFS_IMAGE}:do_image_complete', '', d)} \
"
do_compile[mcdepends] += "${@oe.utils.conditional('INITRAMFS_MULTICONFIG', '', '', 'mc::${INITRAMFS_MULTICONFIG}:${INITRAMFS_IMAGE}:do_image_complete', d)}"
do_compile[vardeps] += "PV_UKI_CMDLINE PV_UKI_CMDLINE_MACHINE PV_BOOT_OEMARGS DISTRO_VERSION"

do_compile() {
	# Without --os-release ukify embeds the build host's /etc/os-release.
	cat > ${B}/os-release <<EOF
NAME="Pantavisor"
ID=pantavisor
VERSION_ID="${DISTRO_VERSION}"
PRETTY_NAME="Pantavisor ${DISTRO_VERSION}"
EOF
	nativepython3 ${STAGING_BINDIR_NATIVE}/ukify build \
		--linux=${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE} \
		--initrd=${INITRAMFS_DEPLOY_DIR_IMAGE}/${INITRAMFS_IMAGE_NAME}.cpio.gz \
		--stub=${DEPLOY_DIR_IMAGE}/linux${EFI_ARCH}.efi.stub \
		--os-release=@${B}/os-release \
		--cmdline="${@' '.join(d.expand('${PV_UKI_CMDLINE} ${PV_UKI_CMDLINE_MACHINE} ${PV_BOOT_OEMARGS}').split())}" \
		--output=${B}/pv-linux.efi
}

do_install[noexec] = "1"

do_deploy() {
	install -m 0644 ${B}/pv-linux.efi ${DEPLOYDIR}/pv-linux.efi
	install -m 0644 ${WORKDIR}/loader.conf ${DEPLOYDIR}/pv-loader.conf
}
addtask deploy after do_compile before do_build
