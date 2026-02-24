/*
 * Copyright (c) 2025-2026 Pantacor Ltd.
 * SPDX-License-Identifier: MIT
 *
 * partfind.h — Find boot partition by number via device path
 */

#ifndef PARTFIND_H
#define PARTFIND_H

#include <efi.h>

/*
 * Find a partition by number on the same disk as the caller's image.
 *   bs:             boot services
 *   caller_device:  device handle of the calling image (for disk scoping)
 *   partition_num:  1-based partition number
 *   out_handle:     receives the matching filesystem handle
 *
 * Returns EFI_SUCCESS if found, EFI_NOT_FOUND otherwise.
 */
EFI_STATUS pv_find_partition(EFI_BOOT_SERVICES *bs,
                             EFI_HANDLE caller_device,
                             UINT32 partition_num,
                             EFI_HANDLE *out_handle);

#endif /* PARTFIND_H */
