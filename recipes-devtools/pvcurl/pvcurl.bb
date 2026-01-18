SUMMARY = "A lightweight curl replacement for Unix Sockets using BusyBox nc"
DESCRIPTION = "Provides curl-compatible CLI for Pantavisor pvcontrol socket communication."
SECTION = "utils"
LICENSE = "MIT"
# Use a generic MIT license checksum typically found in poky
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://pvcurl.sh"

# S points to the directory where the script is located after unpacking
S = "${WORKDIR}"

RDEPENDS:${PN} += "netcat-openbsd"

do_install() {
    # Create the /usr/bin directory in the image rootfs
    install -d ${D}${bindir}
    
    # Install the script as 'pvcurl' (dropping the .sh extension)
    # 0755 sets read/write/execute for owner, and read/execute for others
    install -m 0755 ${S}/pvcurl.sh ${D}${bindir}/pvcurl
}

# Ensure the package contains the file
FILES:${PN} = "${bindir}/pvcurl"

