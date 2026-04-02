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
    
    # Clean up staging directory
    rm -rvf "${STAGING_DIR}"
}

addtask create_tarball after do_unpack before do_build
do_create_tarball[dirs] += "${WORKDIR}"

# Paths relative to the meta-pantavisor layer root, set per-machine in
# kas/machines/<machine>.yaml via local_conf_header.
# PV_FLASH_README      - board/method-specific flashing doc (required)
# PV_FLASH_README_DEPS - space-separated list of method docs to prepend
#                        before PV_FLASH_README (e.g. tezi.md, uuu.md)
# Deployed as: pantavisor.md + deps (in order) + PV_FLASH_README
PV_FLASH_README ??= ""
PV_FLASH_README_DEPS ??= ""

python do_deploy_readme () {
    readme = d.getVar('PV_FLASH_README')
    if not readme:
        return
    import os
    # FILE is the absolute path of this recipe; layer root is 3 dirs up
    # (.../meta-pantavisor/recipes-pv/pantavisor/pantavisor-appengine-distro.bb)
    layer_dir = os.path.dirname(os.path.dirname(os.path.dirname(d.getVar('FILE'))))
    deps = (d.getVar('PV_FLASH_README_DEPS') or '').split()
    paths = [os.path.join(layer_dir, 'docs/pantavisor.md')]
    paths += [os.path.join(layer_dir, dep) for dep in deps]
    paths += [os.path.join(layer_dir, readme)]
    dst = os.path.join(d.getVar('DEPLOY_DIR_IMAGE'), 'pantavisor-README.md')
    parts = []
    for path in paths:
        if os.path.exists(path):
            with open(path) as f:
                parts.append(f.read())
        else:
            bb.warn('pantavisor-README: file not found: %s' % path)
    if parts:
        with open(dst, 'w') as f:
            f.write('\n\n---\n\n'.join(parts))
        bb.note('Deployed pantavisor-README.md to %s' % dst)
}

addtask deploy_readme after do_create_tarball before do_build
