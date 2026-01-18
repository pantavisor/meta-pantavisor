# feature/wasmedge-engine

This branch adds support for the WasmEdge WebAssembly runtime as an engine for Pantavisor.

## Yocto Implementation Details

- **Recipe**: `recipes-wasm/wasmedge/wasmedge_git.bb`
  - Version: 0.14.1
  - Dependencies: `clang`, `libxml2`, `ncurses`, `spdlog`.
- **Kconfig integration**: 
  - `FEATURE_WASMEDGE`: Boolean to toggle the feature.
  - `FEATURE_XCONNECT`: Boolean to toggle `pv-xconnect` service.
- **Architecture Constraints**:
  - Automatically removed for `armv7ve` machines due to build failures in `wasmedge`.
- **KAS configuration**:
  - `kas/bsp-base.yaml` and `kas/appengine-base.yaml` add `meta-clang` repository.
  - LLVM preferred providers are set to `clang` in `conf/distro/panta-distro.inc`.

## Working with this branch

When making changes to Kconfig or features:
1. Update `Kconfig`.
2. Update `kas/bsp-base.yaml` if necessary.
3. Run `.github/scripts/makemachines` to regenerate release configurations.

## Architecture

For the design of the service mesh and `pv-xconnect`, please refer to the documentation in the `pantavisor` source repository:
- `GEMINI.md`: High-level vision.
- `xconnect/XCONNECT.md`: Detailed `pv-xconnect` implementation notes.