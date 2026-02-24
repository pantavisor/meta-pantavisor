/*
 * Copyright (c) 2025-2026 Pantacor Ltd.
 * SPDX-License-Identifier: MIT
 *
 * efivar.c — EFI variable helpers for Pantavisor boot
 */

#include "efivar.h"
#include "pvboot.h"

static EFI_GUID pv_guid = PV_VENDOR_GUID;

BOOLEAN pv_read_clear_tryboot(EFI_RUNTIME_SERVICES *rt)
{
    UINT8 val = 0;
    UINTN size = sizeof(val);
    UINT32 attrs;
    EFI_STATUS status;

    status = rt->GetVariable(PV_VAR_TRYBOOT, &pv_guid,
                             &attrs, &size, &val);
    if (EFI_ERROR(status) || val != 0x01)
        return FALSE;

    /* One-shot: delete immediately */
    rt->SetVariable(PV_VAR_TRYBOOT, &pv_guid,
                    PV_NV_ATTRS, 0, NULL);

    return TRUE;
}

EFI_STATUS pv_set_boot_info(EFI_RUNTIME_SERVICES *rt,
                            UINT32 partition, BOOLEAN tryboot)
{
    EFI_STATUS status;
    CHAR16 part_str[8]; /* Enough for multi-digit partition numbers */
    CHAR16 try_str[2];
    UINTN idx = 0;
    UINT32 tmp;

    /* Convert partition number to wide string */
    if (partition == 0) {
        part_str[0] = L'0';
        idx = 1;
    } else {
        /* Find number of digits */
        CHAR16 rev[8];
        UINTN rlen = 0;
        tmp = partition;
        while (tmp > 0 && rlen < 7) {
            rev[rlen++] = L'0' + (CHAR16)(tmp % 10);
            tmp /= 10;
        }
        /* Reverse into part_str */
        for (UINTN i = 0; i < rlen; i++)
            part_str[i] = rev[rlen - 1 - i];
        idx = rlen;
    }
    part_str[idx] = L'\0';

    try_str[0] = tryboot ? L'1' : L'0';
    try_str[1] = L'\0';

    status = rt->SetVariable(PV_VAR_BOOT_PARTITION, &pv_guid,
                             PV_VOL_ATTRS,
                             (idx + 1) * sizeof(CHAR16), part_str);
    if (EFI_ERROR(status))
        return status;

    status = rt->SetVariable(PV_VAR_BOOT_TRYBOOT, &pv_guid,
                             PV_VOL_ATTRS, sizeof(try_str), try_str);
    return status;
}
