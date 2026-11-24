#!/bin/sh
# Bring up the GPU and report it, then stay up so the result can be read with
# `pvcontrol` / the container log, and so the container can be entered to run
# CUDA by hand.
#
# The driver userspace is the BSP's nvidia driver volume, which pantavisor
# mounts because run.json lists the "nvidia" driver; this is what any GPU
# container has to do to use it.

cat /etc/dgx-os-release

NVIDIA=/usr/local/nvidia
export PATH="$NVIDIA/bin:$PATH"
export LD_LIBRARY_PATH="$NVIDIA/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [ ! -e "$NVIDIA/lib64/libcuda.so.1" ]; then
	echo "pv-nvidia-cuda: no driver volume at $NVIDIA; the BSP or pantavisor predates driver_volumes" >&2
elif nvidia-dev-setup && nvidia-smi && cuda-probe; then
	echo "pv-nvidia-cuda: GPU ready"
else
	echo "pv-nvidia-cuda: GPU check failed" >&2
fi

while :; do
	sleep 3600
done
