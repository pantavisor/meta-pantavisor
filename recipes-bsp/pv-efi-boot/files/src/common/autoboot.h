/*
 * Copyright (c) 2025-2026 Pantacor Ltd.
 * SPDX-License-Identifier: MIT
 *
 * autoboot.h — autoboot.txt parser (RPi-compatible syntax)
 */

#ifndef AUTOBOOT_H
#define AUTOBOOT_H

#include <efi.h>

struct autoboot_config {
    UINT32  boot_partition;   /* Partition number to boot from */
    BOOLEAN tryboot_a_b;      /* Whether A/B tryboot is enabled */
};

/*
 * Parse autoboot.txt from a filesystem handle.
 *   root_fs:    EFI_FILE_PROTOCOL for the root directory
 *   is_tryboot: if TRUE, [tryboot] section overrides [all]
 *   config:     output struct
 *
 * Returns EFI_SUCCESS on success, error status otherwise.
 */
EFI_STATUS pv_parse_autoboot(EFI_FILE_PROTOCOL *root_fs,
                             BOOLEAN is_tryboot,
                             struct autoboot_config *config);

#endif /* AUTOBOOT_H */
