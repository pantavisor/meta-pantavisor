ARCHIVE_DEPLOY_NAME = "Custom tarball from deploy artifacts and SRC_URI files"
DESCRIPTION = "Creates a tarball containing files from DEPLOY_IMAGE_DIR and SRC_URI"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit nopackages

# Add your files via SRC_URI - these will be fetched to WORKDIR
SRC_URI = "${@' '.join(['file://%s' % x for x in d.getVar('WORKDIR_FILES').split()])}"

# This recipe doesn't build anything from source
ALLOW_EMPTY:${PN} = "1"

PV_APPENGINE_CONTAINERS ?= "pantavisor-appengine pantavisor-appengine-netsim pantavisor-appengine-tester"

do_create_tarball[depends] = "${@' '.join(['%s:do_image_complete' % x for x in d.getVar('PV_APPENGINE_CONTAINERS').split()])}"
do_create_tarball[depends] += "pantavisor-bsp:do_compile pv-pvr-sdk:do_deploy"
do_create_tarball[depends] += "pv-example-app:do_image_complete pv-example-norole:do_image_complete"
do_create_tarball[depends] += "pv-example-ready:do_image_complete pv-example-ready-timeout:do_image_complete"
do_create_tarball[depends] += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'xconnect-dbus-systembus', 'pv-example-dbus-host-server:do_image_complete pv-example-dbus-host-server2:do_image_complete pv-example-dbus-host-client:do_image_complete', '', d)}"
do_create_tarball[depends] += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'xconnect-dbus-systembus', 'pv-avahi:do_image_complete pv-avahi-browse:do_image_complete', '', d)}"
do_create_tarball[depends] += "pantavisor-pvtests-local:do_deploy pantavisor-pvtests-remote:do_deploy"

# Define the files you want from DEPLOY_DIR_IMAGE (modify as needed)
DEPLOY_FILES ?= "${@' '.join(['%s-docker.tar' % x for x in d.getVar('PV_APPENGINE_CONTAINERS').split()])}"

# Define files from WORKDIR (SRC_URI files) to include
WORKDIR_FILES ?= "test.docker.sh"

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

    # Copy pvtests tree (local/ and remote/) from deploy dir into staging
    if [ -e "${DEPLOY_DIR_IMAGE}/pvtests" ]; then
        cp -r "${DEPLOY_DIR_IMAGE}/pvtests/." "${STAGING_DIR}/"
    fi

    # Populate generated tarballs from the build into local/common/tarballs/
    mkdir -p "${STAGING_DIR}/local/common/tarballs"
    for f in ${DEPLOY_DIR_IMAGE}/pantavisor-bsp-${MACHINE}.pvrexport.tgz; do
        if [ -e "$f" ]; then
            cp -v "$f" "${STAGING_DIR}/local/common/tarballs/bsp.tgz"
            break
        fi
    done
    for f in ${DEPLOY_DIR_IMAGE}/pv-pvr-sdk.pvrexport.tgz ${DEPLOY_DIR_IMAGE}/pv-pvr-sdk-*.pvrexport.tgz; do
        if [ -e "$f" ]; then
            cp -v "$f" "${STAGING_DIR}/local/common/tarballs/pvr-sdk.tgz"
            break
        fi
    done
    for f in ${DEPLOY_DIR_IMAGE}/pv-example-app.pvrexport.tgz; do
        if [ -e "$f" ]; then
            cp -v "$f" "${STAGING_DIR}/local/common/tarballs/pv-example-app.tgz"
            break
        fi
    done
    for f in ${DEPLOY_DIR_IMAGE}/pv-example-norole.pvrexport.tgz; do
        if [ -e "$f" ]; then
            cp -v "$f" "${STAGING_DIR}/local/common/tarballs/pv-example-norole.tgz"
            break
        fi
    done
    for f in ${DEPLOY_DIR_IMAGE}/pv-example-ready.pvrexport.tgz; do
        if [ -e "$f" ]; then
            cp -v "$f" "${STAGING_DIR}/local/common/tarballs/pv-example-ready.tgz"
            break
        fi
    done
    for f in ${DEPLOY_DIR_IMAGE}/pv-example-ready-timeout.pvrexport.tgz; do
        if [ -e "$f" ]; then
            cp -v "$f" "${STAGING_DIR}/local/common/tarballs/pv-example-ready-timeout.tgz"
            break
        fi
    done
    for f in ${DEPLOY_DIR_IMAGE}/pv-example-dbus-host-server.pvrexport.tgz; do
        if [ -e "$f" ]; then
            cp -v "$f" "${STAGING_DIR}/local/common/tarballs/pv-example-dbus-host-server.tgz"
            break
        fi
    done
    for f in ${DEPLOY_DIR_IMAGE}/pv-example-dbus-host-server2.pvrexport.tgz; do
        if [ -e "$f" ]; then
            cp -v "$f" "${STAGING_DIR}/local/common/tarballs/pv-example-dbus-host-server2.tgz"
            break
        fi
    done
    for f in ${DEPLOY_DIR_IMAGE}/pv-example-dbus-host-client.pvrexport.tgz; do
        if [ -e "$f" ]; then
            cp -v "$f" "${STAGING_DIR}/local/common/tarballs/pv-example-dbus-host-client.tgz"
            break
        fi
    done
    for f in ${DEPLOY_DIR_IMAGE}/pv-avahi.pvrexport.tgz; do
        if [ -e "$f" ]; then
            cp -v "$f" "${STAGING_DIR}/local/common/tarballs/pv-avahi.tgz"
            break
        fi
    done
    for f in ${DEPLOY_DIR_IMAGE}/pv-avahi-browse.pvrexport.tgz; do
        if [ -e "$f" ]; then
            cp -v "$f" "${STAGING_DIR}/local/common/tarballs/pv-avahi-browse.tgz"
            break
        fi
    done

    # Populate remote/common/tarballs/ (shares bsp and pvr-sdk with local)
    mkdir -p "${STAGING_DIR}/remote/common/tarballs"
    cp -v "${STAGING_DIR}/local/common/tarballs/bsp.tgz" \
        "${STAGING_DIR}/remote/common/tarballs/bsp.tgz"
    cp -v "${STAGING_DIR}/local/common/tarballs/pvr-sdk.tgz" \
        "${STAGING_DIR}/remote/common/tarballs/pvr-sdk.tgz"

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
