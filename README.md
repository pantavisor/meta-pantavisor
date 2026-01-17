This README file contains information on the contents of the meta-pantavisor layer.

meta-pantavisor is the center piece of the incubuation Yocto based container distro
for Embedded Linux Products.

Things are still in the making.

For now visit:

 * The github wiki: https://github.com/pantavisor/meta-pantavisor/wiki
 * The pantavisor Forum: https://community.pantavisor.io/

To find information and get support on how to use it.

## Pantavisor Features

The following features can be enabled via `Kconfig` (using `kas-container menu`) or by appending to `PANTAVISOR_FEATURES` in your configuration.

### runc
Adds `runc` (OCI container runtime) support to Pantavisor.
- **Kconfig**: `FEATURE_RUNC` (Default: `y`)
- **PANTAVISOR_FEATURES**: `runc`

### wasmedge
Adds `wasmedge` (WebAssembly runtime) support to Pantavisor.
- **Kconfig**: `FEATURE_WASMEDGE` (Default: `n`)
- **PANTAVISOR_FEATURES**: `wasmedge`
- **Constraints**: Currently disabled for `armv7ve` machines.

| Board | Build(Scarthgap) | Flash | Tested |
| :--- | :--- | :--- | :--- |
| **sunxi-orange-pi-3lts** | [![Schedule - sunxi-orange-pi-3lts-scarthgap](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-sunxi-orange-pi-3lts.yaml/badge.svg)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-sunxi-orange-pi-3lts.yaml) | | |
| **sunxi-orange-pi-r1** | [![Schedule - sunxi-orange-pi-r1-scarthgap](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-sunxi-orange-pi-r1.yaml/badge.svg)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-sunxi-orange-pi-r1.yaml) | | |
| **sunxi-bananapi-m2-berry** | [![Schedule - sunxi-bananapi-m2-berry-scarthgap](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-sunxi-bananapi-m2-berry.yaml/badge.svg)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-sunxi-bananapi-m2-berry.yaml) | | |
| **imx8qxp-b0-mek** | [![Schedule - imx8qxp-b0-mek-scarthgap](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-imx8qxp-b0-mek.yaml/badge.svg)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-imx8qxp-b0-mek.yaml) | | |
| **raspberrypi-armv8** | [![Schedule - raspberrypi-armv8-scarthgap](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-raspberrypi-armv8.yaml/badge.svg)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-raspberrypi-armv8.yaml) | | |
| **colibri-imx6ull** | [![Schedule - colibri-imx6ull-scarthgap](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-colibri-imx6ull.yaml/badge.svg)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-colibri-imx6ull.yaml) | | |
| **radxa-rock5a** | [![Schedule - radxa-rock5a-scarthgap](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-radxa-rock5a.yaml/badge.svg)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-scarthgap-radxa-rock5a.yaml) | | |