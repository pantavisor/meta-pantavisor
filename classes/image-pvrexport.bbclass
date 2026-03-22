inherit container-pvrexport

IMAGE_TYPES_MASKED += " ${@bb.utils.contains('PVROOT_IMAGE', 'no', 'pvrexportit', '', d)} \
	${@bb.utils.contains('PVROOT_IMAGE_BSP', '${IMAGE_BASENAME}', '', ' pvrexportit ', d)} \
	${@bb.utils.contains('IMAGE_BASENAME', 'pantavisor-initramfs', ' pvrexportit ', '', d)} "
# remove pvrexportit from mask if no PVROOT_IMAGE_BSP is defined at all
IMAGE_TYPES_MASKED:remove = "${@'pvrexportit' if not d.getVar('PVROOT_IMAGE_BSP', True) else ''}"

python __anonymous() {
    pn = d.getVar("PN")
    if pn == "pantavisor-initramfs":
        return
    kernel_provider = d.getVar("PREFERRED_PROVIDER_virtual/kernel") or ""
    if not d.getVar("PVROOT_IMAGE_BSP") is None and not pn in d.getVar("PVROOT_IMAGE_BSP") and \
       "linux-dummy" not in kernel_provider:
        d.setVar("PREFERRED_PROVIDER_virtual/kernel", "linux-dummy")
}
