# feature/wasmedge-engine

This branch adds support for the WasmEdge WebAssembly runtime as an engine for Pantavisor.

## Implementation Details

- **Recipe**: `recipes-wasm/wasmedge/wasmedge_git.bb`
  - Version: 0.14.1
  - Dependencies: `clang`, `libxml2`, `ncurses`, `spdlog`.
- **Kconfig integration**: 
  - `FEATURE_WASMEDGE`: Boolean to toggle the feature.
  - `KAS_LOCAL_FEATURE_WASMEDGE`: String to inject `PANTAVISOR_FEATURES:append = " wasmedge"`.
- **Architecture Constraints**:
  - Automatically removed for `armv7ve` machines due to build failures in `wasmedge` (PANTAVISOR_FEATURES:remove:armv7ve).
- **KAS configuration**:
  - `kas/bsp-base.yaml` adds `meta-clang` repository as it's required for building wasmedge.
  - LLVM preferred providers are set to `clang` in `conf/distro/panta-distro.inc`.

## Working with this branch

When making changes to Kconfig or features:
1. Update `Kconfig`.
2. Update `kas/bsp-base.yaml` if necessary (e.g. adding new layers).
3. Run `.github/scripts/makemachines` to regenerate release configurations in `.github/configs/release/`.
