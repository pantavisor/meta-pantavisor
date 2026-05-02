require conf/distro/poky.conf
# mandatory class
IMAGE_CLASSES:append = " image-pvrexport"

TCLIBC ?= "musl"

# Enable advisory rootfs manifest audit by default for the panta distro.
# Set 'pv-manifest-strict' (instead of, or in addition to, 'pv-manifest-audit')
# to gate the build on manifest drift.
PANTAVISOR_FEATURES:append = " pv-manifest-audit"

