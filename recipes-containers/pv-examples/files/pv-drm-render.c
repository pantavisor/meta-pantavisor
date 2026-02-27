#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <xf86drm.h>

int main() {
    int fd = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        perror("Failed to open /dev/dri/renderD128");
        return 1;
    }

    drmVersion *ver = drmGetVersion(fd);
    if (ver) {
        printf("DRM Render (user) success!\n");
        printf("Driver: %s, Version: %d.%d\n", ver->name, ver->version_major, ver->version_minor);
        drmFreeVersion(ver);
    }

    close(fd);
    return 0;
}

