/*
 * Copyright (c) 2025-2026 Pantacor Ltd.
 * SPDX-License-Identifier: MIT
 */

#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

int main() {
    int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        perror("Failed to open /dev/dri/card0");
        return 1;
    }

    drmModeRes *res = drmModeGetResources(fd);
    if (!res) {
        perror("Failed to get DRM resources (KMS)");
        close(fd);
        return 1;
    }

    printf("DRM Master (mgmt) success!\n");
    printf("Connectors: %d, Encoders: %d, CRTCs: %d\n", 
           res->count_connectors, res->count_encoders, res->count_crtcs);

    drmModeFreeResources(res);
    close(fd);
    return 0;
}

