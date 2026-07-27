ARCHIVE_DEPLOY_NAME = "Custom tarball from deploy artifacts and SRC_URI files"
DESCRIPTION = "Creates a tarball containing files from DEPLOY_IMAGE_DIR and SRC_URI"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit nopackages

# Add your files via SRC_URI - these will be fetched to WORKDIR
SRC_URI = "${@' '.join(['file://%s' % x for x in d.getVar('WORKDIR_FILES').split()])}"

# This recipe doesn't build anything from source
ALLOW_EMPTY:${PN} = "1"

# Docker images built for the primary MACHINE and bundled as-is. A device-target
# distro (building this tarball for a real board's MACHINE instead of
# docker-x86_64) sets this to "" — no container is booted against a real device,
# so the arm appengine/netsim/tester images aren't built; only the
# BSP/pvr-sdk/example-app/pvtests tarballs are. The host-side tester it still needs
# (which runs on the build/CI host, not the arm device) is produced by a separate
# same-branch x86-appengine build and bundled by the install tooling, not here —
# multiconfig can't cross-build it in-tree (the i.MX layers' dynamic arm-kernel
# recipe fails to parse for MACHINE=docker-x86_64).
PV_APPENGINE_CONTAINERS ?= "pantavisor-appengine pantavisor-appengine-netsim pantavisor-appengine-tester"

# Example containers staged into targets/<type>/<scope>/. The xconnect set only
# exists when PANTAVISOR_FEATURES carries xconnect-dbus-systembus, so it is appended
# conditionally; the tests that use it are pinned devices=["appengine"] anyway. One
# list drives both the task dependencies and the staging loop below, so the two can't
# drift. A downstream layer adding a container to the suites extends PV_PVTEST_CONTAINERS.
# Target class this build's suites and tarballs are for; see pantavisor-pvtests-local.bb.
PVTEST_TARGET_TYPE ?= "appengine"

PV_PVTEST_CONTAINERS ?= "pv-example-app pv-example-norole pv-example-ready pv-example-ready-timeout pv-example-mgmt"
PV_PVTEST_CONTAINERS_XCONNECT ?= "pv-example-system-dbus-server pv-example-system-dbus-server-collision pv-example-system-dbus-client pv-example-system-dbus-client-denied pv-avahi pv-avahi-browse"
PV_PVTEST_CONTAINERS_ALL = "${PV_PVTEST_CONTAINERS} ${@bb.utils.contains('PANTAVISOR_FEATURES', 'xconnect-dbus-systembus', d.getVar('PV_PVTEST_CONTAINERS_XCONNECT'), '', d)}"

do_create_tarball[depends] = "${@' '.join(['%s:do_image_complete' % x for x in d.getVar('PV_APPENGINE_CONTAINERS').split()])}"
do_create_tarball[depends] += "${@' '.join(['%s:do_image_complete' % x for x in d.getVar('PV_PVTEST_CONTAINERS_ALL').split()])}"
do_create_tarball[depends] += "pantavisor-pvtests-local:do_deploy pantavisor-pvtests-remote:do_deploy pantavisor-pvtests-host:do_deploy"

# Define the files you want from DEPLOY_DIR_IMAGE (modify as needed)
DEPLOY_FILES ?= "${@' '.join(['%s-docker.tar' % x for x in d.getVar('PV_APPENGINE_CONTAINERS').split()])}"

# Host-side files (test.docker.sh, devices.txt, README.md) and the shared
# pvtest/common helpers come from pantavisor-pvtests-host's do_deploy, via
# ${DEPLOY_DIR_IMAGE}/pvtests — the same channel as the local/ and remote/ suites,
# copied into the tarball root below. Kept as an empty extension point for
# downstream bbappends that add their own tarball-root files.
WORKDIR_FILES ?= ""

# Build suffix (using variables available in all recipes)
BUILD_SUFFIX ?= "${@'-' + d.getVar('DISTRO_VERSION') if d.getVar('DISTRO_VERSION') else ''}"

#THE_DEPLOY_NAME = "${PN}-${MACHINE}${BUILD_SUFFIX}-${DATETIME}"

# Output tarball name with build suffix
TARBALL_NAME ?= "${PN}-${MACHINE}${BUILD_SUFFIX}-${DATETIME}.tar.gz"
TARBALL_NAME[vardepsexclude] = "DATETIME"
TARBALL_LINK_NAME ?= "${PN}-${MACHINE}${BUILD_SUFFIX}.tar.gz"

#do_create_tarball[cleandirs] += "${DEPLOY_DIR_IMAGE}/${THE_DEPLOY_NAME}"

do_create_tarball() {
    echo "Creating tarball: ${WORKDIR}/${TARBALL_NAME}"
    echo "Deploy dir: ${DEPLOY_DIR_IMAGE}"
    echo "Work dir: ${WORKDIR}"
    
    # Create temporary staging directory
    STAGING_DIR="${WORKDIR}/tarball_staging"
    rm -rvf "${STAGING_DIR}"
    mkdir -p "${STAGING_DIR}/"
    
    # Add files from DEPLOY_DIR_IMAGE
    if [ -n "${DEPLOY_FILES}" ]; then
        for pattern in ${DEPLOY_FILES}; do
            found_files=""
            for file in ${DEPLOY_DIR_IMAGE}/${pattern}; do
                if [ -e "$file" ]; then
                    found_files="yes"
                    basename_file=$(basename "$file")
                    echo "Adding deploy file: $file as $basename_file"
                    cp -v "$file" "${STAGING_DIR}/"
                fi
            done
            if [ -z "$found_files" ]; then
                bbwarn "No deploy files found matching pattern: $pattern"
            fi
        done
    fi

    # Add files from WORKDIR (SRC_URI files)
    if [ -n "${WORKDIR_FILES}" ]; then
        for filename in ${WORKDIR_FILES}; do
            if [ -e "${WORKDIR}/$filename" ]; then
                echo "Adding workdir file: ${WORKDIR}/$filename as $filename"
                cp -v "${WORKDIR}/$filename" "${STAGING_DIR}/"
                cp -v "${WORKDIR}/$filename" "${DEPLOY_DIR_IMAGE}/"
            else
                bbwarn "Workdir file not found: ${WORKDIR}/$filename"
            fi
        done
    fi

    #mkdir -p ${DEPLOY_DIR_IMAGE}/${BUILD_DEPLOY_NAME}
    #cp -rf ${STAGING_DIR}/* ${DEPLOY_DIR_IMAGE}/${BUILD_DEPLOY_NAME}

    # Copy pvtests tree from deploy dir into staging: the local/ and remote/ suites
    # plus the host-side test.docker.sh, devices.txt, README.md and pvtest/common.
    if [ -e "${DEPLOY_DIR_IMAGE}/pvtests" ]; then
        cp -r "${DEPLOY_DIR_IMAGE}/pvtests/." "${STAGING_DIR}/"
    fi

    # Container exports go into targets/<type>/<scope>/, NOT into the suites'
    # common/tarballs/. Only the tarballs vary by target (arch + signing CA), so the
    # local/ and remote/ trees stay shared and single-copy; test.docker.sh bind-mounts
    # targets/<type>/<scope>/ over /work/<scope>/common/tarballs at tester start. That
    # keeps every test's ../../common/tarballs/<name>.pvrexport.tgz reference — and the
    # five absolute /work/local/common/tarballs/... references in test scripts —
    # working byte-identically for any target.
    #
    # Deploy names are used verbatim: the .pvrexport.tgz suffix comes from
    # container-pvrexport.bbclass, so a board build's deploy dir needs no renaming.
    #
    # bsp/pvr-sdk are NOT staged: tests run against a functional device (the appengine
    # image bakes them into pvtx.d) and each test's initial revision is built from the
    # device's factory clone plus the test's own tarballs.
    tgt_local="${STAGING_DIR}/targets/${PVTEST_TARGET_TYPE}/local"
    tgt_remote="${STAGING_DIR}/targets/${PVTEST_TARGET_TYPE}/remote"
    mkdir -p "$tgt_local" "$tgt_remote"

    # Seed from the checked-in exports the suites ship (pv-oem-developer-001*), which
    # would otherwise be masked by the mount. They are signed by one CA, so a target
    # trusting a different one replaces or drops them.
    for f in "${STAGING_DIR}/local/common/tarballs/"*.pvrexport.tgz; do
        [ -e "$f" ] && cp -v "$f" "$tgt_local/"
    done

    for name in ${PV_PVTEST_CONTAINERS_ALL}; do
        f="${DEPLOY_DIR_IMAGE}/${name}.pvrexport.tgz"
        if [ -e "$f" ]; then
            cp -v "$f" "$tgt_local/"
        else
            bbwarn "pvtest container export not found: $f"
        fi
    done

    # remote/ only ever references pv-example-app.
    cp -v "$tgt_local/pv-example-app.pvrexport.tgz" "$tgt_remote/"

    # Create the tarball
    cd "${STAGING_DIR}"
    tar -czvf "${WORKDIR}/${TARBALL_NAME}" .

    # Copy tarball to deploy directory for easy access
    cp -v "${WORKDIR}/${TARBALL_NAME}" "${DEPLOY_DIR_IMAGE}/"
    echo "Tarball available at: ${DEPLOY_DIR_IMAGE}/${TARBALL_NAME}"

    # Create stable symlink
    cd "${DEPLOY_DIR_IMAGE}"
    rm -f "${TARBALL_LINK_NAME}"
    ln -s "${TARBALL_NAME}" "${TARBALL_LINK_NAME}"
    echo "Stable symlink created: ${DEPLOY_DIR_IMAGE}/${TARBALL_LINK_NAME} -> ${TARBALL_NAME}"

    # Deploy unpacked directory so test.docker.sh can be run without extracting the tarball
    tarball_link="${TARBALL_LINK_NAME}"
    unpacked_name="${tarball_link%.tar.gz}"
    rm -rf "${DEPLOY_DIR_IMAGE}/${unpacked_name}"
    cp -r "${STAGING_DIR}/." "${DEPLOY_DIR_IMAGE}/${unpacked_name}/"
    echo "Unpacked directory available at: ${DEPLOY_DIR_IMAGE}/${unpacked_name}"

    # Clean up staging directory
    rm -rvf "${STAGING_DIR}"
}

addtask create_tarball after do_unpack before do_build
do_create_tarball[dirs] += "${WORKDIR}"
