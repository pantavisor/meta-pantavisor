#!/bin/sh
# Bring up the GPU and report it, then stay up so the result can be read with
# `pvcontrol` / the container log, and so the container can be entered to run
# CUDA by hand.

cat /etc/dgx-os-release

if nvidia-dev-setup && nvidia-smi && cuda-probe; then
	echo "pv-nvidia-cuda: GPU ready"
else
	echo "pv-nvidia-cuda: GPU check failed" >&2
fi

while :; do
	sleep 3600
done
