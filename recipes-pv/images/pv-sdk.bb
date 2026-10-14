SUMMARY = "SDK for building containers, their pvrexports, and Pantavisor"
DESCRIPTION = "populate_sdk target: cross toolchain and sysroot for the \
machine, with the libraries pantavisor builds against, plus pv-mkpvrexport \
to pack a rootfs into a signed container pvrexport. This image's own rootfs \
is shipped in the SDK as the base for 'pv-mkpvrexport --base'."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image

# busybox is static here, so nothing pulls in the C library on its own; the
# base must carry the runtime the SDK's toolchain links against.
IMAGE_INSTALL = " \
	${TCLIBC} \
	base-files \
	base-passwd \
	busybox \
	libgcc \
	libstdc++ \
"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

# image-pvrexport (IMAGE_CLASSES) would also pack this rootfs as a container;
# it only exists to seed the SDK.
IMAGE_FSTYPES = "tar.gz"
IMAGE_FSTYPES:remove = "pvrexportit"

# Keep in step with DEPENDS in pantavisor_git.bb. libevent, libthttp and
# picohttpparser are built static-only; pvtx-static links the C library and
# zlib statically.
TOOLCHAIN_TARGET_TASK:append = " \
	${TCLIBC}-staticdev \
	libevent-dev \
	libevent-staticdev \
	libthttp-dev \
	libthttp-staticdev \
	mbedtls-dev \
	picohttpparser-dev \
	picohttpparser-staticdev \
	zlib-dev \
	zlib-staticdev \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'lxc-next', 'lxc6-pv-dev', 'lxc-pv-dev', d)} \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'dm-crypt', 'libkcapi-dev', '', d)} \
"

TOOLCHAIN_HOST_TASK:append = " nativesdk-pv-sdk-tools"
# Named after the architecture: the docker-* machines are only build hosts
# for it, and "docker" in the installer name would suggest a container image.
PV_SDK_NAME = "${@d.getVar('MACHINE').replace('docker-', '', 1)}"
TOOLCHAIN_OUTPUTNAME = "${IMAGE_BASENAME}-${PV_SDK_NAME}-${SDKMACHINE}"

do_populate_sdk[depends] += "${PN}:do_image_complete"

install_container_base() {
	install -Dm 0644 ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.tar.gz \
		${SDK_OUTPUT}${SDKPATHNATIVE}${prefix_nativesdk}/share/pv-sdk/base-rootfs.tar.gz
}
POPULATE_SDK_POST_HOST_COMMAND:append = " install_container_base"

# rm_work empties rootfs/ after do_image_complete; an image task re-run
# without do_rootfs would then deploy an empty base rootfs into the SDK.
RM_WORK_EXCLUDE += "${PN}"
