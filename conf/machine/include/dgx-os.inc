# What NVIDIA validates for GB10 is a DGX OS release as a whole: one kernel, one
# driver, one CUDA. Pin them together from that release's "Current Software
# Versions" table, https://docs.nvidia.com/dgx/dgx-spark/release-notes.html, not
# from the newest NV-Kernels tag or driver; NVIDIA tags kernels well ahead of
# what DGX OS ships.
#
# scripts/dgx-os-versions checks this file against the release notes and, with
# --update, rewrites it (checksums and kernel defconfig included).

DGX_OS_VERSION = "7.6.0"
DGX_OS_CUDA_VERSION = "13.0.3"

# The release notes name the Ubuntu ABI (7.0.0-1019); NV-Kernels tags it as
# Ubuntu-nvidia-<series>-<abi>.<upload>_24.04.<respin>. Take the last respin and
# pin its commit: NVIDIA rewrites the 24.04_linux-nvidia-*-next branches.
DGX_OS_KERNEL_ABI = "7.0.0-1019"
NV_KERNEL_TAG = "Ubuntu-nvidia-7.0-7.0.0-1019.19_24.04.2"
NV_KERNEL_SRCREV = "ae07646a606b3f18707246b0762464452cb40cbe"
NV_KERNEL_SHA256 = "3b304fb138d12075c8abf5b7d3ba3ec7b582c8a64c3751b73a232c8bfc829853"
NV_KERNEL_LINUX_VERSION = "7.0.14"

# One driver release for the kernel modules, the GSP firmware and the CUDA
# userspace in GPU containers: the driver refuses a mismatched firmware, and
# libcuda a mismatched module.
NVIDIA_DRIVER_VERSION = "580.178.04"
NVIDIA_DRIVER_RUN_SHA256 = "ef59ec5d24850e12d6f7550ec1f7cf84db53a84ce9c63eb3ba55ef5ed0c4f049"
NVIDIA_OPEN_SHA256 = "f30d4c20feda9f570a69084573a72423067e1e2d46c50ca58c391664872a9e01"
