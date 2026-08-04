ARCHIVE_DEPLOY_NAME = "Custom tarball from deploy artifacts and SRC_URI files"
DESCRIPTION = "Creates a tarball containing files from DEPLOY_IMAGE_DIR and SRC_URI"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit nopackages

SRC_URI = "${@' '.join(['file://%s' % x for x in (d.getVar('WORKDIR_FILES') + ' ' + d.getVar('PVTEST_HOST_FILES')).split()])}"

ALLOW_EMPTY:${PN} = "1"

PV_APPENGINE_CONTAINERS ?= "pantavisor-appengine pantavisor-appengine-netsim pantavisor-appengine-tester"

PVTEST_TARGET_TYPE ?= "appengine"

PV_PVTEST_CONTAINERS ?= "pv-example-app pv-example-norole pv-example-ready pv-example-ready-timeout pv-example-mgmt"
PV_PVTEST_CONTAINERS_XCONNECT ?= "pv-example-system-dbus-server pv-example-system-dbus-server-collision pv-example-system-dbus-client pv-example-system-dbus-client-denied pv-avahi pv-avahi-browse"
PV_PVTEST_CONTAINERS_ALL = "${PV_PVTEST_CONTAINERS} ${@bb.utils.contains('PANTAVISOR_FEATURES', 'xconnect-dbus-systembus', d.getVar('PV_PVTEST_CONTAINERS_XCONNECT'), '', d)}"

do_create_tarball[depends] = "${@' '.join(['%s:do_image_complete' % x for x in d.getVar('PV_APPENGINE_CONTAINERS').split()])}"
do_create_tarball[depends] += "${@' '.join(['%s:do_image_complete' % x for x in d.getVar('PV_PVTEST_CONTAINERS_ALL').split()])}"
do_create_tarball[depends] += "pantavisor-pvtests-local:do_deploy pantavisor-pvtests-remote:do_deploy"

DEPLOY_FILES ?= "${@' '.join(['%s-docker.tar' % x for x in d.getVar('PV_APPENGINE_CONTAINERS').split()])}"

WORKDIR_FILES ?= "test.docker.sh device.txt"

# Host-side helpers that land in the tarball under another name or path, so they
# are fetched but not part of the flat WORKDIR_FILES copy. common is a verbatim
# copy of pantavisor's pvtest/common.in: the tester container gets it from the
# pantavisor-pvtest package, the host gets it from here. Keep both in sync.
PVTEST_HOST_FILES ?= "tarball-README.md workspace-README.md common"

BUILD_SUFFIX ?= "${@'-' + d.getVar('DISTRO_VERSION') if d.getVar('DISTRO_VERSION') else ''}"

TARBALL_NAME ?= "${PN}-${MACHINE}${BUILD_SUFFIX}-${DATETIME}.tar.gz"
TARBALL_NAME[vardepsexclude] = "DATETIME"
TARBALL_LINK_NAME ?= "${PN}-${MACHINE}${BUILD_SUFFIX}.tar.gz"

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

    install -m 0644 "${WORKDIR}/tarball-README.md"   "${STAGING_DIR}/README.md"
    install -m 0644 "${WORKDIR}/workspace-README.md" "${STAGING_DIR}/workspace-README.md"
    install -D -m 0644 "${WORKDIR}/common"           "${STAGING_DIR}/pvtest/common"

    # Copy pvtests tree from deploy dir into staging: the local/ and remote/ suites
    if [ -e "${DEPLOY_DIR_IMAGE}/pvtests" ]; then
        cp -r "${DEPLOY_DIR_IMAGE}/pvtests/." "${STAGING_DIR}/"
    fi

    tgt_local="${STAGING_DIR}/targets/${PVTEST_TARGET_TYPE}/local"
    tgt_remote="${STAGING_DIR}/targets/${PVTEST_TARGET_TYPE}/remote"
    mkdir -p "$tgt_local" "$tgt_remote"

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

    # remote/ only ever references pv-example-app
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
