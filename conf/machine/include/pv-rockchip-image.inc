# Turns JeffyCN/meta-rockchip BSP output into a Pantavisor-bootable image.
# Board agnostic; require it from a machine conf.

# rockchip-image.bbclass adds the "wic" fstype, the RK_ROOTFS_TYPE rootfs and
# Rockchip kernel-image handling. Scope it to the system image: a blanket
# INHERIT also hits Pantavisor's container recipes, where an extra "wic"
# fstype trips container-pvrexport.bbclass and breaks the do_deploy that
# pantavisor-starter's do_rootfs_pvroot needs.
IMAGE_CLASSES:append:pn-pantavisor-starter = " rockchip-image"

# .wic.gz (distribution) and .wic.bmap (bmaptool). Same container hazard
# (image_types.bbclass matches "wic.*"), so scope them the same way.
IMAGE_FSTYPES:append:pn-pantavisor-starter = " wic.gz wic.bmap"

# Vendor generic-gptdisk.wks.in leaves the rootfs unlabelled and not
# bootable; ours fixes both (details in the file).
WKS_FILE = "pv-rockchip-gptdisk.wks.in"

# The wks only labels the rootfs inside the .wic. The standalone ext4 that
# gen_rkupdateimg packs into update.img is built separately and needs the
# same LABEL=root, or pv_mount_init() dies with "could not mount '(null)'".
EXTRA_IMAGECMD:ext4:append:pn-pantavisor-starter = " -L root"
