/*
 * Copyright (c) 2025-2026 Pantacor Ltd.
 * SPDX-License-Identifier: MIT
 *
 * partfind.c — Find boot partition by number via UEFI device path
 *
 * Enumerates all SIMPLE_FILE_SYSTEM_PROTOCOL handles, walks their
 * device paths, and matches MEDIA_HARDDRIVE_DP PartitionNumber.
 * Scoped to the same disk as the caller's image.
 */

#include "partfind.h"
#include <efilib.h>

static EFI_GUID dp_guid = EFI_DEVICE_PATH_PROTOCOL_GUID;
static EFI_GUID fs_guid = EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID;

/*
 * Get the disk device path prefix length (everything before the
 * MEDIA_HARDDRIVE_DP node). Used to scope partition search to
 * the same physical disk.
 */
static UINTN disk_path_len(EFI_DEVICE_PATH *dp)
{
    UINTN len = 0;

    while (dp && !IsDevicePathEnd(dp)) {
        if (DevicePathType(dp) == MEDIA_DEVICE_PATH &&
            DevicePathSubType(dp) == MEDIA_HARDDRIVE_DP)
            return len;
        len += DevicePathNodeLength(dp);
        dp = NextDevicePathNode(dp);
    }
    return 0;
}

/*
 * Compare two device path prefixes up to 'len' bytes.
 */
static BOOLEAN path_prefix_match(EFI_DEVICE_PATH *a, EFI_DEVICE_PATH *b,
                                 UINTN len)
{
    UINT8 *pa = (UINT8 *)a;
    UINT8 *pb = (UINT8 *)b;

    for (UINTN i = 0; i < len; i++) {
        if (pa[i] != pb[i])
            return FALSE;
    }
    return TRUE;
}

EFI_STATUS pv_find_partition(EFI_BOOT_SERVICES *bs,
                             EFI_HANDLE caller_device,
                             UINT32 partition_num,
                             EFI_HANDLE *out_handle)
{
    EFI_STATUS status;
    EFI_HANDLE *handles = NULL;
    UINTN count = 0;
    EFI_DEVICE_PATH *caller_dp = NULL;
    UINTN caller_disk_len;

    *out_handle = NULL;

    /* Get caller's device path for disk scoping */
    status = bs->HandleProtocol(caller_device, &dp_guid,
                                (VOID **)&caller_dp);
    if (EFI_ERROR(status))
        return status;

    caller_disk_len = disk_path_len(caller_dp);

    /* Enumerate all filesystem handles */
    status = bs->LocateHandleBuffer(ByProtocol, &fs_guid,
                                    NULL, &count, &handles);
    if (EFI_ERROR(status))
        return status;

    for (UINTN i = 0; i < count; i++) {
        EFI_DEVICE_PATH *dp = NULL;

        status = bs->HandleProtocol(handles[i], &dp_guid, (VOID **)&dp);
        if (EFI_ERROR(status))
            continue;

        /* Walk to find MEDIA_HARDDRIVE_DP node */
        EFI_DEVICE_PATH *node = dp;
        while (node && !IsDevicePathEnd(node)) {
            if (DevicePathType(node) == MEDIA_DEVICE_PATH &&
                DevicePathSubType(node) == MEDIA_HARDDRIVE_DP) {
                HARDDRIVE_DEVICE_PATH *hd = (HARDDRIVE_DEVICE_PATH *)node;
                UINTN this_disk_len = disk_path_len(dp);

                /* Must be same disk and matching partition number */
                if (hd->PartitionNumber == partition_num &&
                    caller_disk_len > 0 &&
                    this_disk_len == caller_disk_len &&
                    path_prefix_match(caller_dp, dp, caller_disk_len)) {
                    *out_handle = handles[i];
                    bs->FreePool(handles);
                    return EFI_SUCCESS;
                }
                break;
            }
            node = NextDevicePathNode(node);
        }
    }

    bs->FreePool(handles);
    return EFI_NOT_FOUND;
}
