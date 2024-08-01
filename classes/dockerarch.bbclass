
DOCKER_PLATFORM_x86_64 = "linux/amd64"
DOCKER_PLATFORM_arm = "linux/arm"
DOCKER_PLATFORM_armv5 = "linux/arm/v5"
DOCKER_PLATFORM_armv6 = "linux/arm/v6"
DOCKER_PLATFORM_aarch64 = "linux/arm64"

DOCKER_PLATFORM ?= "${@d.getVar("DOCKER_PLATFORM_${TUNE_ARCH}", expand=True)}"

DOCKER_ARCH_x86_64 = "amd64"
DOCKER_ARCH_arm = "arm32v6"
DOCKER_ARCH_armv5 = "arm32v5"
DOCKER_ARCH_armv6 = "arm32v6"
DOCKER_ARCH_armv7 = "arm32v7"
DOCKER_ARCH_aarch64 = "arm64v8"

DOCKER_ARCH ?= "${@d.getVar("DOCKER_ARCH_${TUNE_ARCH}", expand=True)}"

