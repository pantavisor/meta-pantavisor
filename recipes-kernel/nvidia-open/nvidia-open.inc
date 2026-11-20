# One driver release for the kernel modules, the GSP firmware and the CUDA
# userspace in GPU containers: the driver refuses a mismatched firmware, and
# libcuda a mismatched module. 580 is the branch DGX OS ships for GB10; 580.178.04
# is what DGX OS 7.6 pairs with linux-nvidia 7.0.0-1019.
NVIDIA_DRIVER_VERSION = "580.178.04"

COMPATIBLE_MACHINE = "dgx-spark"
