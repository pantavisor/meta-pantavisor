SUMMARY = "Pantahub Python Flask Hello World Application Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

# Ensure container is built first
DEPENDS += "flask-helloworld-container"

inherit pvrexport

PANTAHUB_API = "api.pantahub.com"
PANTAHUB_USER ?= "pantavisor-apps"

BB_STRICT_CHECKSUM = "0"

SRC_URI += " \
    file://pv-flask-helloworld_v1.0.0.args.json \
    "

# Additional container runtime arguments for Flask app
PVR_APP_ADD_EXTRA_ARGS += " \
    --volume /var/pvr-volume-boot:boot \
    --volume /var/pvr-volume-revision:revision \
    --volume /var/pvr-volume-permanent:permanent \
    "

# Use the locally loaded Docker image
# First build the container: bitbake flask-helloworld-container
# Then load it to Docker: docker load < tmp/deploy/images/*/flask-helloworld-container-1.0-docker.tar
# Finally build this: bitbake pv-flask-helloworld
# Use Docker reference - requires Docker image to be pre-loaded
# Build sequence:
#   1) bitbake python3-flask-helloworld
#   2) bitbake flask-helloworld-container  
#   3) docker load < tmp/deploy/images/*/flask-helloworld-container-1.0-docker.tar
#   4) bitbake pv-flask-helloworld
PVR_DOCKER_REF = "flask-helloworld:1.0"

# Container name in Pantavisor (removes pv- prefix)
PVCONT_NAME = "flask-helloworld"