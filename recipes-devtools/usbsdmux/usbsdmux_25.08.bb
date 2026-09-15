SUMMARY = "Tool to control an USB-SD-Mux from the command line"
DESCRIPTION = "Controls the Linux Automation / Pengutronix USB-SD-Mux, which \
switches an SD card between a device under test and the host."
HOMEPAGE = "https://github.com/linux-automation/usbsdmux"

LICENSE = "LGPL-2.1-or-later & CC0-1.0"
LIC_FILES_CHKSUM = "file://LICENSES/LGPL-2.1-or-later.txt;md5=4bf661c1e3793e55c8d1051bc5e0ae21 \
                    file://LICENSES/CC0-1.0.txt;md5=65d3616852dbf7b1a6d4b53b00626032"

SRC_URI = "git://github.com/linux-automation/usbsdmux.git;protocol=https;branch=master"
SRCREV = "dc8ea0ea05cd1cf02902fbfebf79061389a69097"

S = "${WORKDIR}/git"

inherit python_setuptools_build_meta

DEPENDS += "python3-setuptools-scm-native"

# setuptools_scm derives the version from git describe. The git fetcher does
# leave a .git behind, but its state is not something to hang a package version
# on, so state it outright.
export SETUPTOOLS_SCM_PRETEND_VERSION = "${PV}"

# contrib/udev is shipped in the tree but not installed by the build. The rules
# create the /dev/usb-sd-mux/id-<serial> symlinks usbsdmux is normally addressed
# by, so without them a lab script has to guess an sg node.
do_install:append() {
    install -d ${D}${nonarch_base_libdir}/udev/rules.d
    install -m 0644 ${S}/contrib/udev/99-usbsdmux.rules ${D}${nonarch_base_libdir}/udev/rules.d/
}

FILES:${PN} += "${nonarch_base_libdir}/udev/rules.d"

# socket/configparser/paho are only reached from the optional mqtt helper, so
# they are deliberately not pulled in.
RDEPENDS:${PN} += "python3-core python3-ctypes python3-fcntl python3-json"
