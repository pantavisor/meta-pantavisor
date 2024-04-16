
DOCKER_ARCH_arm = "linux/arm"
DOCKER_ARCH_armv5 = "linux/arm/v5"
DOCKER_ARCH_armv6 = "linux/arm/v6"
DOCKER_ARCH_aarch64 = "linux/arm/v8"

DOCKER_PLATFORM ?= "${@d.getVar("DOCKER_ARCH_${TUNE_ARCH}", expand=True)}"

