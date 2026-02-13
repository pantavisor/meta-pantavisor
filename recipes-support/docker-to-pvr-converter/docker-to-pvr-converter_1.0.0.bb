SUMMARY = "Docker to PVR Archive Converter"
DESCRIPTION = "Utility to convert Docker container archives to Pantavisor PVR repository format"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

SRC_URI = ""

inherit allarch native

# Path to Docker archive (will be set by dependent recipes)
DOCKER_ARCHIVE_PATH ?= "${DEPLOY_DIR_IMAGE}/flask-helloworld-container-1.0-docker.tar"
PVR_ARCHIVE_NAME ?= "flask-helloworld-1.0.0.tar.gz"
PVR_CONTAINER_NAME = "flask-helloworld"

# JSON configuration files relative to output directory
PVR_CONFIG_JSON = "pvrrepo/.pvr/src.json"
PVR_SIG_JSON = "_sigs/${PVR_CONTAINER_NAME}.json"

do_create_converter[dirs] += "${WORKDIR}"
do_create_converter() {
    mkdir -p ${WORKDIR}/converter
    
    # Create conversion script
    cat > ${WORKDIR}/converter/convert-docker-to-pvr.sh << 'SCRIPT_EOF'
#!/bin/sh
set -e

DOCKER_ARCHIVE="$1"
PVR_OUTPUT_DIR="$2"
PVR_CONTAINER_NAME="$3"
PVR_CONFIG_JSON="$4"
PVR_SIG_JSON="$5"

echo "Converting Docker archive: $DOCKER_ARCHIVE"
echo "To PVR directory: $PVR_OUTPUT_DIR"
echo "Container name: $PVR_CONTAINER_NAME"

# Check if Docker archive exists
if [ ! -f "$DOCKER_ARCHIVE" ]; then
    echo "ERROR: Docker archive not found: $DOCKER_ARCHIVE"
    exit 1
fi

# Create PVR repository structure
PVR_DIR="$PVR_OUTPUT_DIR/${PVR_CONTAINER_NAME}"
mkdir -p "$PVR_DIR/pvrrepo/.pvr"

# Create basic PVR metadata
echo '{"version": "1.0"}' > "$PVR_DIR/pvrrepo/.pvr/config.json"

# Extract Docker archive to PVR directory
echo "Creating PVR repository structure..."
cd "$PVR_DIR"
pvr init

# Extract Docker archive and add contents
tar -xf "$DOCKER_ARCHIVE" --strip-components=1
pvr add .

# Create container configuration using printf to avoid complex quoting issues
printf '{\n    "#spec": "service-manifest-src@1",\n    "docker_config": {\n        "AttachStderr": false,\n        "AttachStdin": false,\n        "AttachStdout": false,\n        "Cmd": ["--host=0.0.0.0", "--port=8080"],\n        "Domainname": "",\n        "Entrypoint": ["/usr/bin/flask-helloworld"],\n        "Env": [\n            "FLASK_ENV=production",\n            "FLASK_HOST=0.0.0.0", \n            "FLASK_PORT=8080",\n            "FLASK_DEBUG=false"\n        ],\n        "Hostname": "",\n        "Image": "",\n        "Labels": null,\n        "OnBuild": null,\n        "OpenStdin": false,\n        "StdinOnce": false,\n        "Tty": false,\n        "User": "",\n        "Volumes": null,\n        "WorkingDir": ""\n    },\n    "docker_name": "%s",\n    "persistence": {\n        "/var/pvr-volume-boot": "boot",\n        "/var/pvr-volume-revision": "revision", \n        "/var/pvr-volume-permanent": "permanent"\n    },\n    "template": "builtin-lxc-docker"\n}\n' "$PVR_CONTAINER_NAME" > "$PVR_DIR/$PVR_CONFIG_JSON"

# Create container signature using printf
printf '{\n    "#spec": "pvs@2",\n    "protected": ""\n}\n' > "$PVR_DIR/$PVR_SIG_JSON"

# Commit to PVR repository
echo "Committing PVR repository..."
pvr commit -m "Convert Docker archive to PVR format"

echo "PVR conversion completed successfully"
echo "Output directory: $PVR_OUTPUT_DIR"
echo "PVR repository: $PVR_DIR/pvrrepo"

# Cleanup
SCRIPT_EOF

    chmod +x ${WORKDIR}/converter/convert-docker-to-pvr.sh
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/converter/convert-docker-to-pvr.sh ${D}${bindir}/convert-docker-to-pvr.sh
}

# Disable compilation since this is just a script installer
do_compile[noexec] = "1"

BBCLASSEXTEND = "native nativesdk"