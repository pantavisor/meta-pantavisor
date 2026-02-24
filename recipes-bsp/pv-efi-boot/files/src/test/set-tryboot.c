/*
 * Copyright (c) 2025-2026 Pantacor Ltd.
 * SPDX-License-Identifier: MIT
 *
 * set-tryboot.efi — Test helper that sets PvTryBoot and chainloads stage1
 *
 * Place as \EFI\BOOT\BOOTX64.EFI on the ESP, rename real stage1 to
 * \pvboot-stage1.efi.  On boot this sets PvTryBoot=1 then loads stage1.
 */

#include <efi.h>
#include <efilib.h>

#include "../common/pvboot.h"

static EFI_GUID pv_guid = PV_VENDOR_GUID;
static EFI_GUID lip_guid = EFI_LOADED_IMAGE_PROTOCOL_GUID;

#define STAGE1_PATH L"\\pvboot-stage1.efi"

EFI_STATUS efi_main(EFI_HANDLE image_handle,
                    EFI_SYSTEM_TABLE *st)
{
    EFI_STATUS status;
    EFI_LOADED_IMAGE *loaded_image;
    EFI_DEVICE_PATH *dp;
    EFI_HANDLE child_handle = NULL;
    UINT8 tryboot_val = 1;

    PV_PRINT(st, L"[TEST] Setting PvTryBoot=1\r\n");

    /* Set the one-shot PvTryBoot NV variable */
    status = st->RuntimeServices->SetVariable(
        PV_VAR_TRYBOOT, &pv_guid, PV_NV_ATTRS,
        sizeof(tryboot_val), &tryboot_val);
    if (EFI_ERROR(status)) {
        PV_PRINT(st, L"[TEST] WARNING: Failed to set PvTryBoot\r\n");
        /* Continue anyway — stage1 will just do normal boot */
    }

    /* Get our own loaded image to find the ESP */
    status = st->BootServices->HandleProtocol(
        image_handle, &lip_guid, (VOID **)&loaded_image);
    if (EFI_ERROR(status)) {
        PV_PRINT(st, L"[TEST] ERROR: Cannot get loaded image\r\n");
        return status;
    }

    /* Build device path to the real stage1 on the ESP */
    dp = FileDevicePath(loaded_image->DeviceHandle, STAGE1_PATH);
    if (!dp) {
        PV_PRINT(st, L"[TEST] ERROR: Cannot build stage1 path\r\n");
        return EFI_OUT_OF_RESOURCES;
    }

    PV_PRINT(st, L"[TEST] Chainloading stage1...\r\n");
    status = st->BootServices->LoadImage(FALSE, image_handle, dp,
                                         NULL, 0, &child_handle);
    FreePool(dp);
    if (EFI_ERROR(status)) {
        PV_PRINT(st, L"[TEST] ERROR: Cannot load stage1\r\n");
        return status;
    }

    status = st->BootServices->StartImage(child_handle, NULL, NULL);
    if (EFI_ERROR(status))
        st->BootServices->UnloadImage(child_handle);

    return status;
}
