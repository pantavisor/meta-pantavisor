SUMMARY = "pv-perf — debug container with linux perf + strace, sharing the host PID namespace"
DESCRIPTION = "On-device profiling and tracing. The container keeps the host PID, \
network and IPC namespaces (lxc.namespace.keep) and holds CAP_SYS_ADMIN \
+ CAP_SYS_PTRACE, so `pventer -c pv-perf perf top -p $(pidof pv-main-loop)` \
profiles pantavisor's hot worker, and `pventer -c pv-perf strace -p $(pidof pv-main-loop)` \
traces its syscalls. Not intended for production images — opt in only when \
you need to profile or trace."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "${PN}"
PVRIMAGE_AUTO_MDEV = "0"

# perf comes from the kernel recipe (linux-raspberrypi here) and pulls
# its runtime libs (libdw, libelf, libunwind, libdebuginfod, libslang,
# libpython3, libstdc++, libz, libcrypto). We add a small shell so the
# operator can pventer in and run things interactively.
IMAGE_INSTALL += "perf busybox strace"

# perf's package only exists when DISTRO_FEATURES has tools-profile.
# The kernel recipe gates the build on that flag too, so without it
# the image-install line above resolves to nothing useful and the
# container is effectively empty. Encode the requirement explicitly
# so the image fails fast with a clear message instead of producing a
# silently-broken container.
python __anonymous() {
    distro_features = (d.getVar("DISTRO_FEATURES") or "").split()
    if "tools-profile" not in distro_features:
        bb.warn("pv-perf: DISTRO_FEATURES is missing 'tools-profile'; "
                "perf will not be in the resulting image. Add it via "
                "kas/with-perf.yaml or local.conf.")
}

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-perf-run.sh \
            file://pv-perf.args.json"

install_pv_perf() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-perf-run.sh ${IMAGE_ROOTFS}${bindir}/pv-perf-run
}

ROOTFS_POSTPROCESS_COMMAND += "install_pv_perf; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-perf-run"

# Skip auto-recovery — when this dies it's almost always because the
# operator killed the perf session, which we don't want to treat as a
# failure that triggers reboots.
PVR_APP_ADD_GROUP = "platform"
