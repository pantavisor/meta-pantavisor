/*
 * Copyright (c) 2025-2026 Pantacor Ltd.
 * SPDX-License-Identifier: MIT
 *
 * pvboot.h — Shared constants for pv-efi-boot
 */

#ifndef PVBOOT_H
#define PVBOOT_H

#include <efi.h>

/* Pantavisor vendor GUID for all EFI variables */
#define PV_VENDOR_GUID \
    { 0xa4e3e45c, 0xb87f, 0x4a56, \
      { 0x90, 0x78, 0x5f, 0x4e, 0x3a, 0x2d, 0x1c, 0x8b } }

/* EFI variable names */
#define PV_VAR_TRYBOOT       L"PvTryBoot"
#define PV_VAR_BOOT_PARTITION L"PvBootPartition"
#define PV_VAR_BOOT_TRYBOOT  L"PvBootTryBoot"

/* File paths */
#define PV_AUTOBOOT_PATH     L"\\autoboot.txt"
#define PV_STAGE2_PATH       L"\\pvboot.efi"
#define PV_UKI_PATH          L"\\pv-linux.efi"

/* EFI variable attributes */
#define PV_NV_ATTRS  (EFI_VARIABLE_NON_VOLATILE | \
                      EFI_VARIABLE_BOOTSERVICE_ACCESS | \
                      EFI_VARIABLE_RUNTIME_ACCESS)
#define PV_VOL_ATTRS (EFI_VARIABLE_BOOTSERVICE_ACCESS | \
                      EFI_VARIABLE_RUNTIME_ACCESS)

/* Error print helper — works without any library beyond ConOut */
#define PV_PRINT(st, msg) \
    (st)->ConOut->OutputString((st)->ConOut, (msg))

/* Maximum autoboot.txt size (must fit one sector) */
#define PV_AUTOBOOT_MAX_SIZE 512

#endif /* PVBOOT_H */
