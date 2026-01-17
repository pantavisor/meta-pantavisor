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

## Future Vision: Container Services & Host Functions

The goal is to allow Pantavisor containers to offer services to WasmEdge apps through standardized host functions.

### Planned Protocols
- **D-Bus**: Implement host functions that allow Wasm apps to communicate with services in other containers via a D-Bus bus managed or bridged by Pantavisor.
- **HTTP/REST**: Provide a mechanism for Wasm apps to reach REST APIs offered by other containers (e.g., via Unix Domain Sockets or internal networking).

### Implementation Strategy
The `pv_wasmedge` plugin in the Pantavisor source should be evolved from a simple wrapper to use the **WasmEdge C API**. This will enable:
1.  Registration of custom host modules (e.g., `pantavisor_dbus`, `pantavisor_http`).
2.  Secure bridging between the isolated Wasm environment and containerized services on the device.
3.  A "capability-based" security model where Wasm apps are granted access to specific container services via Pantavisor configuration.

## Universal Service Broker Concept (LXC/runc/Wasm)

Beyond WasmEdge, the goal is a unified "Service Mesh" where any container can provide a service that Pantavisor manages access to, following the established pattern for kernel drivers.

### Proposed Abstraction
- **Exports (`services.json`)**: A file within a container (e.g., `services.json`) that declares what services it provides (D-Bus names, REST endpoints, etc.). This mirrors how the `bsp/` container uses `drivers.json` to export available aliases.
- **Requirements (`run.json`)**: A container requests access to services in its `run.json` manifest. This mirrors the existing `drivers` section.

#### Example Requirement in `run.json`:
```json
{
  "#spec": "service-manifest-run@1",
  "name": "my-app",
  "services": {
    "optional": ["audio-service"],
    "required": ["network-manager"]
  },
  "drivers": {
    "optional": ["wifi"]
  },
  "type": "lxc"
}
```

### Broker (Pantavisor) Responsibility
Pantavisor acts as the **Security Broker**:
- **LXC/runc**: Dynamically maps specific sockets or namespaces and enforces D-Bus policies based on the `required` list.
- **Wasm**: Injects specific Host Functions or WasmEdge Plugins only for the authorized services.

### Benefits
- **Decoupling**: Containers use logical service names; Pantavisor handles the low-level plumbing.
- **Security**: Isolation is the default. Access is granted only via explicit `run.json` requirements.
- **Consistency**: High-level APIs remain the same regardless of whether the provider is an LXC container or a Wasm module.

## High-Performance Data Paths (FD Passing & Shared Memory)

For use cases like video playback or sensor streaming, REST is insufficient. The Broker must support zero-copy data transfer.

### Mechanism: UDS + SCM_RIGHTS
- **FD Passing**: Pantavisor's virtual socket bridge must support intercepting and forwarding File Descriptors (SCM_RIGHTS).
- **Shared Memory**: Providers can pass shared memory handles (e.g., dmabuf, memfd) to clients.
- **Wasm Integration**: Since Wasm apps cannot natively handle Unix FD passing, the `pv_wasmedge` host functions will provide an abstraction (e.g., `pv_map_shared_memory(service_name)`) that handles the `mmap` on the host side and exposes the buffer to the Wasm guest.

### Security
Pantavisor remains the arbiter of these handles. It can verify that an FD being passed from a provider actually matches the type of service authorized in the consumer's `run.json`.

## Raw Socket Mediation & Identity

For non-REST protocols (raw Unix sockets), identity injection is handled via:

1.  **The Greeting Packet**: For Pantavisor-native services, the Broker sends a JSON context header (`{"client": "...", "role": "..."}`) as the very first packet after connection establishment.
2.  **Ancillary Data (cmsg)**: Metadata is passed via `recvmsg` control blocks, allowing identity to be transmitted out-of-band without modifying the application stream.
3.  **Role-Based Sockets**: For legacy apps, Pantavisor connects to different physical sockets on the provider side based on the authorized role of the client (e.g., `service.admin.sock` vs `service.viewer.sock`).

## D-Bus Mediation & Virtual Bus

D-Bus is the standard for high-level services like NetworkManager and Bluetooth. Pantavisor acts as a **D-Bus Policy Proxy**.

### Mechanism
- **Virtual Bus Socket**: Pantavisor provides a unique `/run/pv/services/dbus.sock` to each consumer.
- **Interface Filtering**: Access is restricted to specific D-Bus Names and Interfaces declared in the container's `run.json`.
- **Message Inspection**: The Broker inspects D-Bus method calls and signals, silently dropping or rejecting those not in the authorized allow-list.
- **Role Enforcement**: Pantavisor can rewrite or inject metadata into the D-Bus header to ensure the provider knows the client's authorized role.

## The `pv-xconnect` Architecture

To manage these interactions efficiently, a dedicated process called `pv-xconnect` handles the mediation logic via on-demand plugins. It runs as a single-threaded process driven by `libevent`.

### Core Process Responsibilities
- **Discovery & Reconciliation**: Consumes an `xconnect-graph` from Pantavisor's `pv-ctrl` socket and maintains the state of active connects.
- **Plumbing Helpers**: Provides a "Toolbox" of namespace-aware helpers (e.g., `inject_unix_socket`, `inject_devnode`) so plugins don't have to manage low-level `setns()` logic.
- **Security**: Acts as the single point of truth for role-based access control.

### Plugin-Driven Injection
Plugins are responsible for triggering the resource injection into the container. This ensures that the specific needs of a protocol (e.g., a Wayland socket vs. a DRM device node) are handled correctly.

1.  **Reconciliation**: Core identifies a new connect and loads the required plugin.
2.  **Setup**: Core calls `plugin->on_link_added(link)`.
3.  **Injection**: The plugin calls a core helper to plant the virtual resource (socket/device) inside the consumer's namespace.
4.  **Mediation**: The plugin attaches the resulting File Descriptors to the shared `libevent` base for data processing.

### Plugin Types
- **`type: rest`**: Intercepts HTTP/UDS, injects `X-PV-Client` and `X-PV-Role` headers.
- **`type: dbus`**: Acts as a D-Bus policy proxy, filtering interfaces and method calls.
- **`type: unix`**: Handles raw packet/stream forwarding with support for SCM_RIGHTS (FD passing).
- **`type: drm`**: Filters DRI/DRM device nodes to provide secure hardware acceleration.
- **`type: wayland`**: Mediates the Wayland protocol for isolated UI rendering.
- **`type: input`**: Routes and filters input events (touch, keys) to authorized containers.
