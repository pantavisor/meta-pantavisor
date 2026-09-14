SUMMARY = "Universal Update Utility"
DESCRIPTION = "Image deploy tool for i.MX chips"
HOMEPAGE = "https://github.com/nxp-imx/mfgtools"

# Copy of meta-freescale's recipes-devtools/uuu/uuu_git.bb (scarthgap), plus one
# musl patch. It lives here because the lab-controller machines
# (raspberrypi-armv8, orangepi-5b) do not pull meta-freescale, and pv-labutils
# needs uuu to flash i.MX targets. Keep PV/SRCREV in sync with meta-freescale
# scarthgap.
#
# meta-freescale only ever builds this on glibc; on this distro's musl,
# libuuu/buffer.cpp fails on the LFS64 names (stat64, mmap64) that musl 1.2.4
# stopped exposing under _GNU_SOURCE.
SRC_URI = "git://github.com/nxp-imx/mfgtools.git;protocol=https;branch=master \
           file://0001-libuuu-use-plain-stat-mmap-on-non-glibc-Linux.patch \
"
SRCREV = "79ce7d2b2e7459e7b7c94f902d172c30b08884ab"
PV = "1.5.233"

LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=38ec0c18112e9a92cffc4951661e85a5"

inherit cmake pkgconfig

S = "${WORKDIR}/git"

DEPENDS = "libusb zlib bzip2 openssl zstd libtinyxml2"

BBCLASSEXTEND = "native nativesdk"

# meta-freescale ships the same recipe at the same BBFILE_PRIORITY (5), so on an
# NXP machine the two tie: bitbake resolves a same-PV tie by sort order today and
# goes fatal ("Multiple versions of uuu are due to be built") the moment the PVs
# drift. Stand down and let meta-freescale's copy win.
python __anonymous() {
    if 'freescale-layer' in (d.getVar('BBFILE_COLLECTIONS') or '').split():
        raise bb.parse.SkipRecipe('provided by meta-freescale')
}
