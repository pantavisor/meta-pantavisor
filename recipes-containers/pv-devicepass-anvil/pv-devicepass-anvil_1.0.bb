SUMMARY = "DevicePass Anvil — local Ethereum testnet with DevicePassRegistry"
DESCRIPTION = "Foundry Anvil container providing a local Ethereum testnet \
for DevicePass on-chain identity verification."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit pvrexport

PVR_DOCKER_REF = "ghcr.io/foundry-rs/foundry:latest"

SRC_URI += "file://${BPN}.services.json \
            file://${BPN}.args.json \
            file://${BPN}.network.json \
            file://${BPN}.config.json"

PVR_APP_ADD_EXTRA_ARGS += "--group=app"
