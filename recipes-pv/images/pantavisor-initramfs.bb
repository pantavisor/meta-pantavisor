inherit image image-buildinfo

# Simple initramfs image artifact generation for tiny images.
DESCRIPTION = "Pantavisor enabled Initramfs image for Pantavisor BSPs"

IMAGE_BUILDINFO_FILE = "${sysconfdir}/build"

VIRTUAL-RUNTIME_dev_manager ?= "busybox-mdev"
VIRTUAL-RUNTIME_init_manager = "pantavisor"
VIRTUAL-RUNTIME_pantavisor_config ??= "pantavisor-config"

PACKAGE_INSTALL = "pantavisor \
	${VIRTUAL-RUNTIME_pantavisor_config} \
	dropbear-pv \
	busybox \
	base-passwd \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'rngd', 'rng-tools', '', d)} \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'automod', 'kmod', '', d)} \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'pvcontrol', 'curl pvcontrol', '', d)} \
	${ROOTFS_BOOTSTRAP_INSTALL}"

IMAGE_TYPES_MASKED += " pvbspit pvrexportit"

# Do not pollute the initrd image with rootfs features
IMAGE_FEATURES = ""
AGL_FEATURES = ""

IMAGE_BASENAME = "pantavisor-initramfs"
IMAGE_NAME_SUFFIX ?= ""
IMAGE_LINGUAS = ""

LICENSE = "MIT"

# don't actually generate an image, just the artifacts needed for one
IMAGE_FSTYPES = "${INITRAMFS_FSTYPES}"

DEPENDS:append = " pvr-native \
	squashfs-tools-native \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', 'lz4-native', '', d)} \
"


EXTRA_IMAGEDEPENDS = ""
UBOOT_ENV = ""
KERNEL_DEPLOY_DEPEND = ""

NO_RECOMMENDATIONS = "1"

IMAGE_FSTYPES:remove = "pvbspit pvrexportit"
IMAGE_TYPES:remove = "pvbspit pvrexportit"

IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# Use the same restriction as initramfs-live-install
COMPATIBLE_HOST = "(i.86|x86_64|aarch64|arm|mips|riscv).*-linux"

ROOTFS_POSTINSTALL_COMMAND += "do_finish_rootfs"

do_finish_rootfs() {
        install -d ${IMAGE_ROOTFS}/volumes
        install -d ${IMAGE_ROOTFS}/exports
        install -d ${IMAGE_ROOTFS}/writable
        
        # Ensure /run exists as a directory
        install -d ${IMAGE_ROOTFS}/run
        
        # Remove /var/run if it exists as a directory (not a symlink)
        if [ -d ${IMAGE_ROOTFS}/var/run ] && [ ! -L ${IMAGE_ROOTFS}/var/run ]; then
                rm -rf ${IMAGE_ROOTFS}/var/run
        fi
        
        # Create symlink from /var/run to /run
        ln -sf ../run ${IMAGE_ROOTFS}/var/run

        # Create /run/pantavisor/pv directory structure
        install -d ${IMAGE_ROOTFS}/run/pantavisor/pv
        
        # Handle /pv -> /run/pantavisor/pv symlink
        if [ -e ${IMAGE_ROOTFS}/pv ]; then
                # /pv exists, check if it's a directory
                if [ -d ${IMAGE_ROOTFS}/pv ] && [ ! -L ${IMAGE_ROOTFS}/pv ]; then
                        # Move any existing content from /pv to /run/pantavisor/pv
                        if [ "$(ls -A ${IMAGE_ROOTFS}/pv)" ]; then
                                cp -a ${IMAGE_ROOTFS}/pv/* ${IMAGE_ROOTFS}/run/pantavisor/pv/
                        fi
                        rm -rf ${IMAGE_ROOTFS}/pv
                fi
        fi
        
        # Create symlink from /pv to /run/pantavisor/pv (only if it doesn't exist)
        if [ ! -e ${IMAGE_ROOTFS}/pv ]; then
                ln -sf run/pantavisor/pv ${IMAGE_ROOTFS}/pv
        fi
        if [ ! -e ${IMAGE_ROOTFS}/media ]; then
                ln -sf run/pantavisor/media ${IMAGE_ROOTFS}/media
        fi
        if [ ! -e ${IMAGE_ROOTFS}/configs ]; then
                ln -sf run/pantavisor/configs ${IMAGE_ROOTFS}/configs
        fi
        
        #ln -sfr ${IMAGE_ROOTFS}/usr/bin/pantavisor ${IMAGE_ROOTFS}/sbin/init
        rm -rf ${IMAGE_ROOTFS}/usr/lib/opkg
}

unset do_fetch[noexec]
unset do_unpack[noexec]
addtask do_rootfs after do_fetch do_unpack
