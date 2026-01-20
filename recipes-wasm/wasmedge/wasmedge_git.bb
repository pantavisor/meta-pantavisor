DESCRIPTION = "Builds WasmEdge from the 0.14.1 release"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=86d3f3a95c324c9479bd8986968f4327"

TOOLCHAIN = "clang"

# Specify the software version.
PV = "0.14.1"

# Source code location.  Use the Git repository and specify the tag.
SRC_URI = "git://github.com/WasmEdge/WasmEdge.git;protocol=https;nobranch=1"

# Specify the exact git revision.  This is important for reproducibility.
SRCREV = "2900031c24f3c49ad3596244dba4c5723048c8ad"

# Set up the source code subdirectory.
S = "${WORKDIR}/git"

# Define the dependency on CMake and other tools.
DEPENDS += "cmake-native libxml2 ncurses spdlog clang clang-native"

RDEPENDS:${PN} += "ncurses"

inherit cmake

# Specify the configurations for cmake.
EXTRA_OECMAKE += " \
    -DCMAKE_SKIP_RPATH=ON \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF \
    -DCMAKE_INSTALL_RPATH="" \
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
    -DWASMEDGE_BUILD_STATIC_LIB=OFF \
    -DWASMEDGE_BUILD_SHARED_LIB=ON \
    -DWASMEDGE_BUILD_TESTS=OFF \
    -DWASMEDGE_BUILD_TOOLS=ON \
    -DWASMEDGE_BUILD_PLUGINS=OFF \
    -DWASMEDGE_BUILD_EXAMPLE=OFF \
    -DWASMEDGE_USE_LLVM=ON \
    -DWASMEDGE_LINK_LLVM_STATIC=OFF \
    -DWASMEDGE_LINK_TOOLS_STATIC=OFF \
    -DWASMEDGE_BUILD_RUNTIME=ON \
    -DLLVM_TOOLS_BINARY_DIR=${STAGING_DIR_NATIVE}/usr/bin \
"

