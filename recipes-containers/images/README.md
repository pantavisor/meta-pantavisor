# Flask Hello World Container

This directory contains the Flask Hello World container recipe for Pantavisor.

## Build Instructions

The container uses a manual `docker load` step because the pvrexport tool requires a locally available Docker image.

### Build Sequence

```bash
# 1. Build the Python Flask application package
bitbake python3-flask-helloworld

# 2. Build the Docker container image
bitbake flask-helloworld-container

# 3. Load the Docker image into Docker daemon
# Find the image tarball in your build directory, e.g.:
docker load < build/tmp-scarthgap/deploy/images/raspberrypi-armv8/flask-helloworld-container-1.0-docker.tar

# 4. Build the pvrexport (Pantavisor export)
bitbake pv-flask-helloworld
```

### Output

After step 4, the pvrexport will be generated at:
```
build/tmp-scarthgap/deploy/images/raspberrypi-armv8/pv-flask-helloworld-1.0.0.pvrexport.tgz
```

## Container Details

- **Image name**: flask-helloworld
- **Tag**: 1.0
- **Port**: 8080
- **Entry point**: /usr/bin/flask-helloworld

## Files

- `flask-helloworld-container.bb` - Docker container image recipe
