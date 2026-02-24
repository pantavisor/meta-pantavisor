/*
 * Copyright (c) 2025-2026 Pantacor Ltd.
 * SPDX-License-Identifier: MIT
 *
 * efivar.h — EFI variable helpers for Pantavisor boot
 */

#ifndef EFIVAR_H
#define EFIVAR_H

#include <efi.h>

/*
 * Read and delete the one-shot PvTryBoot variable.
 * Returns TRUE if tryboot was requested, FALSE otherwise.
 */
BOOLEAN pv_read_clear_tryboot(EFI_RUNTIME_SERVICES *rt);

/*
 * Set volatile boot info variables for Linux to read.
 *   partition: partition number that was booted (e.g. 2 or 3)
 *   tryboot:   TRUE if this is a tryboot
 */
EFI_STATUS pv_set_boot_info(EFI_RUNTIME_SERVICES *rt,
                            UINT32 partition, BOOLEAN tryboot);

#endif /* EFIVAR_H */
