/*
 * Copyright (c) 2025-2026 Pantacor Ltd.
 * SPDX-License-Identifier: MIT
 *
 * pv-efi-boot stage 2 — UKI loader
 *
 * Lives on the active boot partition (A or B).
 * Loads the Unified Kernel Image (pv-linux.efi) which contains
 * kernel + initramfs + cmdline in a single signed PE binary.
 */

#include <efi.h>
#include <efilib.h>

#include "../common/pvboot.h"

static EFI_GUID lip_guid = EFI_LOADED_IMAGE_PROTOCOL_GUID;

EFI_STATUS efi_main(EFI_HANDLE image_handle,
                    EFI_SYSTEM_TABLE *st)
{
    EFI_STATUS status;
    EFI_LOADED_IMAGE *loaded_image;
    EFI_HANDLE uki_handle = NULL;
    EFI_DEVICE_PATH *dp;

    /* InitializeLib already called by _entry in libgnuefi */

    PV_PRINT(st, L"pv-efi-boot stage2\r\n");

    /* Step 1: Get our own loaded image to find the boot partition */
    status = st->BootServices->HandleProtocol(
        image_handle, &lip_guid, (VOID **)&loaded_image);
    if (EFI_ERROR(status)) {
        PV_PRINT(st, L"ERROR: Cannot get loaded image\r\n");
        return status;
    }

    if (!loaded_image->DeviceHandle) {
        PV_PRINT(st, L"ERROR: No device handle\r\n");
        return EFI_NOT_FOUND;
    }

    /*
     * Step 2: Build a device path to pv-linux.efi on our partition.
     * FileDevicePath() combines the device handle's device path
     * with a file path node — so LoadImage can open it directly
     * from the filesystem without buffering into memory.
     */
    dp = FileDevicePath(loaded_image->DeviceHandle, PV_UKI_PATH);
    if (!dp) {
        PV_PRINT(st, L"ERROR: Cannot build UKI device path\r\n");
        return EFI_OUT_OF_RESOURCES;
    }

    /* LoadImage with device path — firmware reads file, verifies sig, measures TPM */
    PV_PRINT(st, L"Loading UKI...\r\n");
    status = st->BootServices->LoadImage(FALSE, image_handle, dp,
                                         NULL, 0, &uki_handle);
    FreePool(dp);
    if (EFI_ERROR(status)) {
        PV_PRINT(st, L"ERROR: Cannot load UKI image\r\n");
        return status;
    }

    /* Step 3: StartImage — UKI boots with embedded kernel/initrd/cmdline */
    PV_PRINT(st, L"Starting UKI...\r\n");
    status = st->BootServices->StartImage(uki_handle, NULL, NULL);

    /* If we get here, the UKI failed to boot — clean up */
    PV_PRINT(st, L"ERROR: UKI failed to start\r\n");
    st->BootServices->UnloadImage(uki_handle);
    return status;
}
