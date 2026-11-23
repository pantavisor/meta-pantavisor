# Flashing: NVIDIA DGX Spark

**Flash method:** write the disk image to the internal NVMe from a live USB Linux

**Image artifact:** `pantavisor-starter-dgx-spark.rootfs.wic` (+ `.wic.bmap`), about 1.1 GB

**Build:** `./kas-container build kas/build-configs/release/nvidia-dgx-spark-scarthgap.yaml` — see the
[build config table](/meta-pantavisor/overview/build-system#build-configs).

:::warning Bring-up status
Built and tested in QEMU (update, reboot, BSP update and rollback), not yet
booted on hardware. Needs a Pantavisor with the `sdboot` bootloader type.
Secure Boot must be disabled.
:::

## Hardware overview

The DGX Spark is built around the **NVIDIA GB10** (10x Cortex-X925 +
10x Cortex-A725, Blackwell iGPU, 128 GB unified LPDDR5X). Unlike other
Pantavisor boards it has no U-Boot and no device tree: AMI UEFI firmware
starts the OS from the NVMe ESP and describes the hardware with ACPI.

| Device | Driver | Notes |
|---|---|---|
| NVMe M.2 2242 | `nvme` (built in) | Holds both the ESP and `/storage` |
| RJ-45 10 GbE (RTL8127) | `r8127` (built in) | Only in NVIDIA's kernel; up without any container asking |
| ConnectX-7, 2x QSFP | `mlx5_core` (module) | Powered off at boot with no cable |
| Wi-Fi 7 (MT7925) | `mt7925e` (module, alias `wifi`) | Firmware in `firmware.squashfs` |
| Blackwell iGPU | `nvidia*` open modules 580.178.04 (alias `nvidia`) | GSP firmware in `firmware.squashfs` |
| HDMI | `simpledrm` from the UEFI framebuffer | Console on `tty0` |

The kernel is NVIDIA's `linux-nvidia` (the DGX OS kernel, recipe
`linux-nvidia-dgx`); mainline does not bring up USB or the Ethernet ports on
GB10 yet.

## Boot chain

```
UEFI firmware ─► EFI/BOOT/BOOTAA64.EFI (systemd-boot) ─► EFI/Linux/pv-<rev>.efi (UKI) ─► pantavisor
```

The UKI bundles the kernel, the Pantavisor initramfs and the kernel command
line. The BSP ships it as `bsp/pantavisor.efi` (`"uki"` in `bsp/run.json`), so
a revision updates the kernel and Pantavisor together. The image's GPT has two
partitions:

| # | Label | Contents |
|---|---|---|
| 1 | `ESP` (vfat, 512 MB) | `EFI/BOOT/BOOTAA64.EFI`, `loader/loader.conf`, `EFI/Linux/pv-<rev>.efi` (`pv-0.efi` as flashed) |
| 2 | `root` (ext4) | `/trails/0` and the rest of `/storage`; grown to fill the disk on first boot |

Pantavisor runs with `PV_BOOTLOADER_TYPE=sdboot`:
- It copies each revision's UKI to `EFI/Linux/pv-<rev>.efi`.
- It boots a new revision once, through systemd-boot's `LoaderEntryOneShot`.
- When the revision commits, it becomes the default (`LoaderEntryDefault`).

A revision that fails therefore falls back to the last good one. To see which
entry booted and which is the default, run this in the `pvr-sdk` container:

```bash
for v in LoaderEntrySelected LoaderEntryDefault LoaderEntryOneShot; do
    printf '%s=' $v
    tail -c +5 /sys/firmware/efi/efivars/$v-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f 2>/dev/null | tr -d '\0'
    echo
done
```

Besides the usual Pantavisor arguments, the command line carries what DGX OS
sets on GB10. Extend it per build with `PV_BOOT_OEMARGS`:

```
console=tty0 pci=pcie_bus_safe initcall_blacklist=tegra234_cbb_init,power_wrap_init kho=off
```

## GPU

The BSP carries NVIDIA's open GPU kernel modules and the GSP firmware they
boot the GPU with, both from driver release 580.178.04
(`recipes-kernel/nvidia-open/`). They load only when a container asks for the
`nvidia` alias in its `args.json`:

```json
"PV_DRIVERS_REQUIRED": ["nvidia"]
```

The CUDA userspace (`libcuda`, `libnvidia-ml`, `nvidia-smi`) is not in the
BSP. It is glibc-only, so it goes in the GPU container. It must be
the exact release of the kernel modules, so update the BSP and the GPU container
in the same revision. NGC CUDA images leave `libcuda` out, expecting
nvidia-container-toolkit to inject it; there is no such injection here.

`nvidia-peermem` is built but is an empty stub without MLNX OFED, so there is no
alias for it; GPUDirect RDMA with the ConnectX-7 uses DMA-BUF instead.

### The `pv-nvidia-cuda` container

`pv-nvidia-cuda` carries that userspace. It is built from the same driver
`.run` as the GSP firmware, so its release always matches the BSP's
(`recipes-containers/nvidia/`). Because the userspace needs glibc, the DGX Spark
configuration builds with glibc (`TCLIBC = "glibc"` in
`kas/machines/nvidia-dgx-spark.yaml`) instead of the musl most Pantavisor
machines use. It is not in the image by default. To add it to
the initial trail, set this in `local.conf` or a kas `local_conf_header`:

```bitbake
PVROOT_CONTAINERS_CORE:append = " pv-nvidia-cuda"
```

Or build it alone and install the export with `pvr`:

```bash
./kas-container build kas/build-configs/release/nvidia-dgx-spark-scarthgap.yaml --target pv-nvidia-cuda
# -> build/tmp-scarthgap/deploy/images/dgx-spark/pv-nvidia-cuda.pvrexport.tgz
```

At start it:

1. Prints `/etc/dgx-os-release`, the DGX OS release it was built against.
2. Runs `nvidia-dev-setup`. This creates `/dev/nvidiactl`, `/dev/nvidia<N>`
   and `/dev/nvidia-uvm*`; the modules register char majors but no nodes. It
   stops if the loaded module is from a different driver release than the
   container.
3. Runs `nvidia-smi`, then `cuda-probe`, which initialises the CUDA driver API
   and creates a context on each GPU.

Read the result in the container's log, from the `pvr-sdk` container:

```bash
cat /storage/logs/current/pv-nvidia-cuda/lxc/console.log
```

```
CUDA driver API 13.0, 1 device(s)
  0: NVIDIA GB10, sm_121, ... MiB
pv-nvidia-cuda: GPU ready
```

A GPU application container needs the same pieces: `"PV_DRIVERS_REQUIRED":
["nvidia"]` in its args, `nvidia-driver-userspace` (plus
`nvidia-driver-userspace-smi` for `nvidia-smi`) and `pv-nvidia-utils` in
`IMAGE_INSTALL`, and `nvidia-dev-setup` run before the application.
`recipes-containers/nvidia/pv-nvidia-cuda.bb` is the template.

## Kernel, driver and CUDA versions

NVIDIA validates GB10 software as a whole DGX OS release. Each release pins one
kernel, one driver and one CUDA version. The
[DGX Spark release notes](https://docs.nvidia.com/dgx/dgx-spark/release-notes.html)
list them under "Current Software Versions". This layer follows that table,
not the newest NV-Kernels tag: NVIDIA tags kernels well before DGX OS ships
them. All the pins live in one file, `conf/machine/include/dgx-os.inc`:

| Variable | Pinned | Used by |
|---|---|---|
| `DGX_OS_VERSION` | 7.6.0 | `/etc/dgx-os-release` |
| `DGX_OS_KERNEL_ABI`, `NV_KERNEL_TAG`, `NV_KERNEL_SRCREV` | 7.0.0-1019, `Ubuntu-nvidia-7.0-7.0.0-1019.19_24.04.2` | `linux-nvidia-dgx` |
| `NVIDIA_DRIVER_VERSION` | 580.178.04 | `nvidia-open-kernel-modules`, `nvidia-gsp-firmware`, `nvidia-driver-userspace` |
| `DGX_OS_CUDA_VERSION` | 13.0.3 | `/etc/dgx-os-release`; the CUDA a toolkit in an app container should not exceed |

Check the pins against the current DGX OS release:

```bash
scripts/dgx-os-versions
```

```
                         pinned (dgx-os.inc)                        DGX OS 7.6.0
DGX_OS_VERSION           7.6.0                                      7.6.0
DGX_OS_KERNEL_ABI        7.0.0-1019                                 7.0.0-1019
...
NV-Kernels already tags Ubuntu-nvidia-7.0-7.0.0-1026.27_24.04.1; DGX OS has not shipped it, so it is not followed.

In sync with DGX OS 7.6.0.
```

It exits 1 when DGX OS has moved on. Then, `--update` rewrites `dgx-os.inc`
with the new tag, commit, checksums and `LINUX_VERSION`. It also regenerates
`recipes-kernel/linux/linux-nvidia-dgx/defconfig` from the new tag's Ubuntu
annotations, reusing tarballs already in `build/downloads`:

```bash
scripts/dgx-os-versions --update
```

After an update, check that `dgx-spark.cfg` still applies, then rebuild the BSP
and `pv-nvidia-cuda` and ship them in one revision.

On the device, the running versions are in the container:

```bash
cat /etc/dgx-os-release          # what the container was built against
cat /proc/driver/nvidia/version  # the loaded kernel module
uname -r                         # the kernel
```

## Flash

Flashing erases DGX OS. Keep the
[DGX Spark recovery media](https://docs.nvidia.com/dgx/dgx-spark/system-recovery.html)
at hand to go back.

### 1. Disable Secure Boot

1. Connect an HDMI display and a USB keyboard directly to the Spark (no hub).
2. Power on and hold **Esc** or **Del** until the UEFI setup menu appears.
3. **Security → Secure Boot → Secure Boot: Disabled**, then **Save & Exit**.

### 2. Write the image

Boot any aarch64 live Linux from a USB stick (**Boot Override** on the
**Save & Exit** tab), copy the image to it and write it to the NVMe:

```bash
lsblk                       # find the internal NVMe, usually /dev/nvme0n1
sudo bmaptool copy pantavisor-starter-dgx-spark.rootfs.wic /dev/nvme0n1
```

Without `bmaptool`, `sudo dd if=pantavisor-starter-dgx-spark.rootfs.wic of=/dev/nvme0n1 bs=4M conv=fsync`
does the same, more slowly.

### 3. Boot

Remove the USB stick and reboot. The firmware finds `EFI/BOOT/BOOTAA64.EFI` on
the NVMe ESP; systemd-boot shows its menu for 3 seconds and starts the default
entry, `pv-0.efi` on a freshly flashed disk.
If the firmware boots something else, pick the NVMe under **Boot Override**.

## Notes

- There is no documented serial console; the console is the HDMI output.
  `console=tty0` is set explicitly: GB10 firmware can publish an ACPI SPCR
  table, and without a `console=` the kernel follows it to a UART instead of
  the screen.
- The kernel config is generated from NVIDIA's Ubuntu annotations with
  `scripts/annotations2config.py`; Pantavisor's changes on top of it are in
  `recipes-kernel/linux/linux-nvidia-dgx/dgx-spark.cfg`.
