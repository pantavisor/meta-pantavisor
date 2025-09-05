
do_image_oci[depends] += "skopeo-native:do_populate_sysroot"
# Append to the function using the _append() syntax
IMAGE_CMD:oci:append() {
    cd ${IMGDEPLOYDIR} 

    skopeo copy --additional-tag="${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}" oci-archive:$image_name.tar docker-archive:${IMAGE_BASENAME}-$image_tag-docker.tar
}
