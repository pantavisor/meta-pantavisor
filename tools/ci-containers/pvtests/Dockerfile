FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV VERBOSE=false

RUN apt-get update && apt-get install -y --no-install-recommends \
    binfmt-support \
    git \
    jq \
    iw \
    wget \
    ca-certificates \
    curl \
    gnupg \
    kmod \
    bc \
    sudo \
    bash \
    util-linux \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
    docker-ce-cli \
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
