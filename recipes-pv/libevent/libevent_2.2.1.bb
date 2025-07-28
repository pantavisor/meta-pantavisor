SUMMARY = "An asynchronous event notification library"
DESCRIPTION = "A software library that provides asynchronous event \
notification. The libevent API provides a mechanism to execute a callback \
function when a specific event occurs on a file descriptor or after a \
timeout has been reached. libevent also supports callbacks triggered \
by signals and regular timeouts"
HOMEPAGE = "http://libevent.org/"
BUGTRACKER = "https://github.com/libevent/libevent/issues"
SECTION = "libs"
DEPENDS = "mbedtls"

LICENSE = "BSD-3-Clause & MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=eaea438df011ea096feec284927c59e0"

SRC_URI = "${GITHUB_BASE_URI}/download/release-2.2.1-alpha/libevent-2.2.1-alpha-dev.tar.gz \
	file://undef_ssl_renegotiation.patch \
	file://bev_finalize_cb.patch \
"
SRC_URI[sha256sum] = "36d0726e570fc2ee61a0a27cfb6bf2799e14a28d030a7473a7a2411f7533d359"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

S = "${WORKDIR}/${BPN}-${PV}-alpha-dev"

PACKAGECONFIG ??= "debug-mode mbedtls static"
PACKAGECONFIG[debug-mode] = "--enable-debug-mode,--disable-debug-mode,"
PACKAGECONFIG[clock-gettime] = "--enable-clock-gettime,--disable-clock-gettime,"
PACKAGECONFIG[dependency-tracking] = "--enable-dependency-tracking,--disable-dependency-tracking,"
PACKAGECONFIG[libevent-regress] = "--enable-libevent-regress,--disable-libevent-regress,"
PACKAGECONFIG[mbedtls] = "--enable-mbedtls,--disable-mbedtls,mbedtls"
PACKAGECONFIG[openssl] = "--enable-openssl,--disable-openssl,openssl"
PACKAGECONFIG[samples] = "--enable-samples,--disable-samples,"
PACKAGECONFIG[shared] = "--enable-shared,--disable-shared,"
PACKAGECONFIG[static] = "--enable-static,--disable-static,"
PACKAGECONFIG[thread-support] = "--enable-thread-support,--disable-thread-support,"

inherit autotools pkgconfig github-releases

PACKAGES_DYNAMIC = "^${PN}-.*$"
python split_libevent_libs () {
    do_split_packages(d, '${libdir}', r'^libevent_([a-z]*)-.*\.so\..*', '${PN}-%s', '${SUMMARY} (%s)', prepend=True, allow_links=True)
}
PACKAGESPLITFUNCS =+ "split_libevent_libs"
