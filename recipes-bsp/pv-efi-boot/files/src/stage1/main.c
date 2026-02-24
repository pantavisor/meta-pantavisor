/*
 * Copyright (c) 2025-2026 Pantacor Ltd.
 * SPDX-License-Identifier: MIT
 *
 * pv-efi-boot stage 1 — ESP boot selector
 *
 * Lives on the ESP (partition 1), never updated.
 * Reads autoboot.txt, handles tryboot, chainloads stage 2 from
 * the target boot partition.
 */

#include <efi.h>
#include <efilib.h>

#include "../common/pvboot.h"
#include "../common/efivar.h"
#include "../common/autoboot.h"
#include "../common/partfind.h"

static EFI_GUID lip_guid = EFI_LOADED_IMAGE_PROTOCOL_GUID;
static EFI_GUID fs_guid = EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID;
static EFI_GUID fi_guid = { 0x09576e92, 0x6d3f, 0x11d2,
    { 0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b } };

/*
 * Load and start an EFI binary from a filesystem handle.
 * Uses buffer-based LoadImage with NULL device path.
 */
static EFI_STATUS load_and_start(EFI_BOOT_SERVICES *bs,
                                 EFI_HANDLE image_handle,
                                 EFI_HANDLE fs_handle,
                                 CHAR16 *path)
{
    EFI_STATUS status;
    EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *fs;
    EFI_FILE_PROTOCOL *root;
    EFI_FILE_PROTOCOL *file;
    EFI_FILE_INFO *info;
    UINTN info_size;
    CHAR8 info_buf[sizeof(EFI_FILE_INFO) + 256];
    VOID *file_buf;
    UINTN file_size;
    EFI_HANDLE child_handle = NULL;

    status = bs->HandleProtocol(fs_handle, &fs_guid, (VOID **)&fs);
    if (EFI_ERROR(status))
        return status;

    status = fs->OpenVolume(fs, &root);
    if (EFI_ERROR(status))
        return status;

    status = root->Open(root, &file, path, EFI_FILE_MODE_READ, 0);
    root->Close(root);
    if (EFI_ERROR(status))
        return status;

    /* Get file size */
    info = (EFI_FILE_INFO *)info_buf;
    info_size = sizeof(info_buf);
    status = file->GetInfo(file, &fi_guid, &info_size, info);
    if (EFI_ERROR(status)) {
        file->Close(file);
        return status;
    }

    file_size = info->FileSize;

    status = bs->AllocatePool(EfiLoaderData, file_size, &file_buf);
    if (EFI_ERROR(status)) {
        file->Close(file);
        return status;
    }

    status = file->Read(file, &file_size, file_buf);
    file->Close(file);
    if (EFI_ERROR(status)) {
        bs->FreePool(file_buf);
        return status;
    }

    /*
     * LoadImage with source buffer. Pass NULL for DevicePath since
     * we're loading from a buffer — firmware will still verify
     * signatures and measure into TPM.
     */
    status = bs->LoadImage(FALSE, image_handle, NULL,
                           file_buf, file_size, &child_handle);
    bs->FreePool(file_buf);
    if (EFI_ERROR(status))
        return status;

    /*
     * Patch child's DeviceHandle so it can locate its own filesystem.
     * LoadImage with NULL device path leaves DeviceHandle unset.
     */
    {
        EFI_LOADED_IMAGE *child_image;
        status = bs->HandleProtocol(child_handle, &lip_guid,
                                     (VOID **)&child_image);
        if (!EFI_ERROR(status))
            child_image->DeviceHandle = fs_handle;
    }

    status = bs->StartImage(child_handle, NULL, NULL);

    /* If StartImage fails or returns, unload the child */
    if (EFI_ERROR(status))
        bs->UnloadImage(child_handle);

    return status;
}

EFI_STATUS efi_main(EFI_HANDLE image_handle,
                    EFI_SYSTEM_TABLE *st)
{
    EFI_STATUS status;
    EFI_LOADED_IMAGE *loaded_image;
    EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *esp_fs;
    EFI_FILE_PROTOCOL *esp_root;
    struct autoboot_config config;
    BOOLEAN is_tryboot;
    EFI_HANDLE target_handle;
    UINT32 fallback_partition;

    /* InitializeLib already called by _entry in libgnuefi */

    PV_PRINT(st, L"pv-efi-boot stage1\r\n");

    /* Step 1: Read and clear one-shot tryboot variable */
    is_tryboot = pv_read_clear_tryboot(st->RuntimeServices);

    if (is_tryboot)
        PV_PRINT(st, L"Tryboot requested\r\n");

    /* Step 2: Get our own filesystem (ESP) */
    status = st->BootServices->HandleProtocol(
        image_handle, &lip_guid, (VOID **)&loaded_image);
    if (EFI_ERROR(status)) {
        PV_PRINT(st, L"ERROR: Cannot get loaded image protocol\r\n");
        return status;
    }

    status = st->BootServices->HandleProtocol(
        loaded_image->DeviceHandle, &fs_guid, (VOID **)&esp_fs);
    if (EFI_ERROR(status)) {
        PV_PRINT(st, L"ERROR: Cannot get ESP filesystem\r\n");
        return status;
    }

    /* Step 3: Read and parse autoboot.txt */
    status = esp_fs->OpenVolume(esp_fs, &esp_root);
    if (EFI_ERROR(status)) {
        PV_PRINT(st, L"ERROR: Cannot open ESP volume\r\n");
        return status;
    }

    status = pv_parse_autoboot(esp_root, is_tryboot, &config);
    esp_root->Close(esp_root);
    if (EFI_ERROR(status)) {
        PV_PRINT(st, L"WARNING: Cannot parse autoboot.txt, using defaults\r\n");
        config.boot_partition = 2;
        config.tryboot_a_b = FALSE;
        is_tryboot = FALSE;
    }

    /* Step 4: Set volatile EFI variables for Linux */
    status = pv_set_boot_info(st->RuntimeServices,
                              config.boot_partition, is_tryboot);
    if (EFI_ERROR(status))
        PV_PRINT(st, L"WARNING: Cannot set boot info variables\r\n");

    /* Step 5: Find target boot partition */
    status = pv_find_partition(st->BootServices,
                               loaded_image->DeviceHandle,
                               config.boot_partition,
                               &target_handle);
    if (EFI_ERROR(status)) {
        PV_PRINT(st, L"ERROR: Boot partition not found\r\n");
        goto fallback;
    }

    /* Step 6: Load and start stage 2 from target partition */
    PV_PRINT(st, L"Loading stage2...\r\n");
    status = load_and_start(st->BootServices, image_handle,
                            target_handle, PV_STAGE2_PATH);
    if (!EFI_ERROR(status))
        return EFI_SUCCESS; /* stage 2 booted kernel, won't reach here */

    PV_PRINT(st, L"Stage2 failed on target partition\r\n");

fallback:
    /* Step 7: Fallback — only if this was a tryboot attempt */
    if (!is_tryboot || !config.tryboot_a_b) {
        PV_PRINT(st, L"FATAL: Boot failed, no fallback available\r\n");
        return EFI_LOAD_ERROR;
    }

    /* Determine fallback partition: re-parse without tryboot to get [all] */
    status = esp_fs->OpenVolume(esp_fs, &esp_root);
    if (EFI_ERROR(status)) {
        PV_PRINT(st, L"FATAL: Cannot reopen ESP for fallback\r\n");
        return status;
    }

    status = pv_parse_autoboot(esp_root, FALSE, &config);
    esp_root->Close(esp_root);
    if (EFI_ERROR(status)) {
        PV_PRINT(st, L"FATAL: Cannot parse autoboot.txt for fallback\r\n");
        return status;
    }

    fallback_partition = config.boot_partition;
    PV_PRINT(st, L"Falling back to default partition\r\n");

    /* Update volatile vars to reflect fallback (no longer tryboot) */
    pv_set_boot_info(st->RuntimeServices, fallback_partition, FALSE);

    status = pv_find_partition(st->BootServices,
                               loaded_image->DeviceHandle,
                               fallback_partition,
                               &target_handle);
    if (EFI_ERROR(status)) {
        PV_PRINT(st, L"FATAL: Fallback partition not found\r\n");
        return status;
    }

    status = load_and_start(st->BootServices, image_handle,
                            target_handle, PV_STAGE2_PATH);
    if (EFI_ERROR(status))
        PV_PRINT(st, L"FATAL: Fallback boot failed\r\n");

    return status;
}
