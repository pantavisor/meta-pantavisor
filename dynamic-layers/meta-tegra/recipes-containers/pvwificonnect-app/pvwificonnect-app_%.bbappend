# Dogfooding the Pantahub builder on the Nano: pvwificonnect's feat/oem-network
# branch package, which reads a Wi-Fi network preset in the OEM config. Drop
# this once a pvwificonnect release carries it.
PVWIFICONNECT_PKG = "v1.9.3-5-g2a7ffa3-feat-oem-network"
PVWIFICONNECT_PKG_URI = "https://gitlab.com/api/v4/projects/pantacor%2Fpvwificonnect/packages/generic/pvwificonnect/${PVWIFICONNECT_PKG}"

SRC_URI:jetson-nano-devkit = " \
    ${PVWIFICONNECT_PKG_URI}/pvwificonnect.${PVWIFICONNECT_PKG}.src.tar.gz;name=oemsrc; \
    ${PVWIFICONNECT_PKG_URI}/pvwificonnect.${PVWIFICONNECT_PKG}.vendor.tar.gz;name=oemvendor;subdir=src/${GO_IMPORT} \
"
SRC_URI[oemsrc.sha256sum] = "abc4f1b705399857c435d80f75a036217fbef8df4bb5e2eae010353e9af4b3d8"
SRC_URI[oemvendor.sha256sum] = "357bb7b3f910a236d5f15be704cc025a9ba7267402a6f1c3c5dd9960ff6acf0e"
