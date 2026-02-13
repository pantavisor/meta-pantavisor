SUMMARY = "Pantavisor Flask Hello World Container Image"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

inherit pantavisor-docker

# Docker image configuration
DOCKER_IMAGE_NAME = "flask-helloworld"
DOCKER_IMAGE_TAG = "1.0"
DOCKER_IMAGE_EXTRA_TAGS = "latest"

# Container entrypoint configuration
OCI_IMAGE_ENTRYPOINT = "/usr/bin/flask-helloworld"
PV_DOCKER_IMAGE_ENTRYPOINT_ARGS = "--host=0.0.0.0 --port=8080"
PV_DOCKER_IMAGE_ENVS = "FLASK_ENV=production FLASK_HOST=0.0.0.0 FLASK_PORT=8080 FLASK_DEBUG=false"

# Container shell (minimal)
CONTAINER_SHELL = "busybox"

# Install required packages
CORE_IMAGE_EXTRA_INSTALL += " \
    python3-flask-helloworld \
    ${CONTAINER_SHELL} \
    python3-core \
    python3-flask \
    python3-compression \
"

# Container configuration
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

# Base packages for minimal container
IMAGE_INSTALL = " \
    base-files \
    base-passwd \
    netbase \
    ${CONTAINER_SHELL} \
"

# Workaround for /var/volatile
ROOTFS_POSTPROCESS_COMMAND += "rootfs_fixup_var_volatile ; "
rootfs_fixup_var_volatile () {
    install -m 1777 -d ${IMAGE_ROOTFS}/${localstatedir}/volatile/tmp
    install -m 755 -d ${IMAGE_ROOTFS}/${localstatedir}/volatile/log
}

# Ensure container works without specific kernel
IMAGE_CONTAINER_NO_DUMMY = "1"

# Add container metadata
DESCRIPTION = "Container running Python Flask Hello World application with modern styling"

# Automatically generate PVR archive after Docker image
do_generate_pvr_archive[depends] += "docker-to-pvr-converter-native:do_populate_sysroot"
do_generate_pvr_archive[dirs] += "${WORKDIR}"
do_generate_pvr_archive() {
    echo "Generating PVR archive from Docker image..."
    
    # Run converter to create PVR format archive
    ${WORKDIR}/converter/convert-docker-to-pvr.sh \
        "${DEPLOY_DIR_IMAGE}/flask-helloworld-container-1.0-docker.tar" \
        "${DEPLOY_DIR_IMAGE}" \
        "flask-helloworld"
    
    # Create symlink for easier access
    if [ -f "${DEPLOY_DIR_IMAGE}/flask-helloworld-1.0.0.tar.gz" ]; then
        ln -sf "flask-helloworld-1.0.0.tar.gz" "${DEPLOY_DIR_IMAGE}/flask-helloworld.pvr.tar.gz"
    fi
}

addtask generate_pvr_archive after do_image_complete before do_build