FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV VERBOSE=false

RUN apt-get update && apt-get install -y --no-install-recommends \
    binfmt-support \
    docker.io \
    git \
    jq \
    iw \
    wget \
    ca-certificates \
    curl \
    gnupg \
    kmod \
    sudo \
    bash \
    util-linux \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/qemu

RUN wget -q https://pantavisor-ci.s3.amazonaws.com/qemu/1303841432/qemu-arm \
    -O qemu-arm \
    && wget -q https://pantavisor-ci.s3.amazonaws.com/qemu/1303841432/qemu-aarch64 \
    -O qemu-aarch64 \
    && chmod +x qemu-arm qemu-aarch64 \
    && mv qemu-arm /usr/local/bin/ \
    && mv qemu-aarch64 /usr/local/bin/

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /work

RUN useradd -m -s /bin/bash pvtester \
    && echo "pvtester ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
