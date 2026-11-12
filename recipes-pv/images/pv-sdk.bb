SUMMARY = "SDK for building containers, their pvrexports, and Pantavisor"
DESCRIPTION = "populate_sdk target: cross toolchain and sysroot for the \
machine, with the libraries pantavisor builds against, plus pv-mkpvrexport \
to pack a rootfs into a signed container pvrexport. This image's own rootfs \
is shipped in the SDK as the base for 'pv-mkpvrexport --base'."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image populate_sdk_qt6_base

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

TOOLCHAIN_TARGET_TASK:append = " packagegroup-pv-sdk-target"

TOOLCHAIN_HOST_TASK:append = " nativesdk-pv-sdk-tools"
# python3-cryptography and other Rust-based modules cross-build from the SDK.
SDK_TOOLCHAIN_LANGS:append = " rust"
# Added by populate_sdk_qt6_base; would add a static library for every package.
SDKIMAGE_FEATURES:remove = "staticdev-pkgs"
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

# A summary of the SDK for releases.json, next to the installer: the toolchain
# and the software the SDK ships on purpose (what packagegroup-pv-sdk-target
# and nativesdk-pv-sdk-tools pull in directly), by recipe and upstream
# version. The .target/.host.manifest beside it list every package.
# Read from pkgdata rather than the manifests: those carry the Debian-renamed
# package names (zlib-dev is libz-dev there), not the ones the recipes use.
python write_sdk_contents () {
    import json, re
    from oe.packagedata import read_pkgdatafile

    def subpkgdata(pkgdata_dir, pkg):
        fn = os.path.join(pkgdata_dir, 'runtime', pkg)
        if not os.path.exists(fn):
            rprov = os.path.join(pkgdata_dir, 'runtime-rprovides', pkg)
            providers = sorted(os.listdir(rprov)) if os.path.isdir(rprov) else []
            if not providers:
                return None
            pkg = providers[0]
            fn = os.path.join(pkgdata_dir, 'runtime', pkg)
        return {k.replace(':' + pkg, ''): v for k, v in read_pkgdatafile(fn).items()}

    # Packagegroups are expanded, not listed: their version says nothing.
    def recipes(pkgdata_dir, root, strip=''):
        found, seen, todo = {}, set(), [root]
        while todo:
            pkg = todo.pop()
            if pkg in seen:
                continue
            seen.add(pkg)
            data = subpkgdata(pkgdata_dir, pkg)
            if data is None:
                bb.warn("write_sdk_contents: no pkgdata for %s" % pkg)
                continue
            if pkg == root or data['PN'].startswith((strip + 'packagegroup-', 'packagegroup-')):
                todo.extend(bb.utils.explode_deps(data.get('RDEPENDS', '')))
                continue
            found[data['PN'][len(strip):] if data['PN'].startswith(strip) else data['PN']] = data['PKGV']
        return dict(sorted(found.items()))

    # gcc-cross-canadian-aarch64 13.3.0-r0 -> gcc 13.3.0
    toolchain = {}
    with open(d.getVar('SDK_HOST_MANIFEST')) as f:
        for line in f:
            name, _, ver = line.split()
            m = re.match(r'(.+)-cross-canadian-', name)
            if m:
                toolchain[m.group(1)] = re.sub(r'^\d+:|-r\d+.*$', '', ver)
    libc = subpkgdata(d.getVar('PKGDATA_DIR'), d.getVar('TCLIBC'))
    if libc:
        toolchain[libc['PN']] = libc['PKGV']

    contents = {
        'toolchain': dict(sorted(toolchain.items())),
        'host': recipes(d.getVar('PKGDATA_DIR_SDK'), 'nativesdk-pv-sdk-tools', 'nativesdk-'),
        'target': recipes(d.getVar('PKGDATA_DIR'), 'packagegroup-pv-sdk-target'),
    }
    out = os.path.join(d.getVar('SDKDEPLOYDIR'), d.getVar('TOOLCHAIN_OUTPUTNAME') + '.contents.json')
    with open(out, 'w') as f:
        json.dump(contents, f, indent=1)
        f.write('\n')
}
SDK_POSTPROCESS_COMMAND:append = " write_sdk_contents"

# rm_work empties rootfs/ after do_image_complete; an image task re-run
# without do_rootfs would then deploy an empty base rootfs into the SDK.
RM_WORK_EXCLUDE += "${PN}"
