# The pv-sdk installer, installed: ghcr.io/pantavisor/pv-sdk:<tag>-<arch>.
# The SDK is relocated to /opt/pv-sdk when installed, so anything that
# copies it out of this image must keep it at that path.
#
# Build context: a directory holding the installer as pv-sdk.sh.

FROM docker.io/library/debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587 AS install
# What the installer itself needs: xz for its payload, python3 and file to
# relocate it.
RUN apt-get update \
	&& DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends file python3 xz-utils \
	&& rm -rf /var/lib/apt/lists/*
COPY pv-sdk.sh /tmp/pv-sdk.sh
RUN sh /tmp/pv-sdk.sh -y -d /opt/pv-sdk && rm /tmp/pv-sdk.sh

FROM docker.io/library/debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587
# The SDK has cmake, meson, ninja, autotools and pkg-config, but no make.
RUN apt-get update \
	&& DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends make \
	&& rm -rf /var/lib/apt/lists/*
COPY --from=install /opt/pv-sdk /opt/pv-sdk
WORKDIR /src
