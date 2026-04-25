SUMMARY = "Agentic mock camera — cycles through bundled JPEG frames, exports the camera-feed service"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "agentic-camera-mock"
PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "python3-core python3-json python3-netserver busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

# Drop-in replacement for agentic-camera-feed: exports the same xconnect
# service name ("camera-feed") with the same /subscribe NDJSON protocol,
# but frames are real JPEGs bundled in at build time.
#
# Sample images are BSD-licensed OpenCV test data, pinned to the 4.10.0
# release tag for reproducible SHAs.

OPENCV_SAMPLES_BASE = "https://raw.githubusercontent.com/opencv/opencv/4.10.0/samples/data"

SRC_URI += "file://agentic-camera-mock.py \
            file://agentic-camera-mock.services.json \
            ${OPENCV_SAMPLES_BASE}/fruits.jpg;name=img1;downloadfilename=mock-fruits.jpg;unpack=0 \
            ${OPENCV_SAMPLES_BASE}/baboon.jpg;name=img2;downloadfilename=mock-baboon.jpg;unpack=0 \
            ${OPENCV_SAMPLES_BASE}/basketball1.png;name=img3;downloadfilename=mock-basketball1.png;unpack=0 \
            ${OPENCV_SAMPLES_BASE}/messi5.jpg;name=img4;downloadfilename=mock-messi5.jpg;unpack=0 \
            ${OPENCV_SAMPLES_BASE}/home.jpg;name=img5;downloadfilename=mock-home.jpg;unpack=0"

SRC_URI[img1.sha256sum] = "9c031d80a1c52da5eca790db896baffec6a7e52bf786cdb7bbfca5c7f880e6a1"
SRC_URI[img2.sha256sum] = "1a1dd18d78eec44420af3b0b7f08ee3d41c982916cae3ce203d7ff35d754cc0f"
SRC_URI[img3.sha256sum] = "ba06f6701f7260998b430c39b6557f775497e6ce7b1a74f0b7ea6af371bf54a6"
SRC_URI[img4.sha256sum] = "1d570e49654e84c7a943918537bd9e5e1ef82920152e147c834006e235be97c9"
SRC_URI[img5.sha256sum] = "23b8cf46a1965d0ec33459b875aed43187802834db49e0daa9fa2cc842e9d8d2"

IMAGES_INSTALL_DIR = "${datadir}/agentic-camera-mock/images"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/agentic-camera-mock.py ${IMAGE_ROOTFS}${bindir}/agentic-camera-mock

    install -d ${IMAGE_ROOTFS}${IMAGES_INSTALL_DIR}
    for f in mock-fruits.jpg mock-baboon.jpg mock-basketball1.png mock-messi5.jpg mock-home.jpg; do
        install -m 0644 ${WORKDIR}/$f ${IMAGE_ROOTFS}${IMAGES_INSTALL_DIR}/$f
    done
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/agentic-camera-mock --config=Cmd=/run/camera/feed.sock"
