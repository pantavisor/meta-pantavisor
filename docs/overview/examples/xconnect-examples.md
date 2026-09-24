---
sidebar_position: 1
---
# xconnect Example Containers

The `pv-examples` containers in `recipes-containers/pv-examples/` demonstrate pv-xconnect service mesh patterns. For the underlying xconnect concepts and manifest format, see the [pantavisor xconnect overview](../../../pantavisor/overview/xconnect.md) and [reference](../../../pantavisor/reference/pantavisor-xconnect.md).

## Overview

| Pattern | Provider | Consumer(s) | Description |
|---------|----------|-------------|-------------|
| Unix Socket | `pv-example-unix-server` | `pv-example-unix-client` | Raw Unix domain socket proxy |
| REST | `pv-example-rest-server` | `pv-example-rest-client` | HTTP-over-UDS with identity injection |
| D-Bus | `pv-example-dbus-server` | `pv-example-dbus-client` | Policy-aware D-Bus proxy |
| D-Bus (hosted) | `pv-example-system-dbus-server` | `pv-example-system-dbus-client` | Pantavisor-hosted system bus, single-pid apps |
| DRM | `pv-example-drm-provider` | `pv-example-drm-master`, `pv-example-drm-render` | Device node injection |
| Wayland | `pv-example-wayland-server` | `pv-example-wayland-client` | Wayland compositor access |

Auto-recovery containers:

| Container | Group | Description |
|-----------|-------|-------------|
| `pv-example-recovery` | root | Crashes after 10s, `on-failure` with `backoff_policy="10min"` |
| `pv-example-stabilize` | root | Fails 3× then stabilizes, `backoff_policy="reboot"` |
| `pv-example-random` | root | Random exit timing, `always` policy |
| `pv-example-app-crash` | app | Inherits app group's auto_recovery |

## Building Example Containers

```bash
# Build specific containers
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-unix-server --target pv-example-unix-client

# Build with workspace (when iterating on pantavisor source)
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-unix-server --target pv-example-unix-client
```

Output: `build/tmp-scarthgap/deploy/images/docker-x86_64/<name>.pvrexport.tgz`

## Quick Test Setup

```bash
mkdir -p pvtx.d
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-*.pvrexport.tgz pvtx.d/

docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
docker exec pva-test lxc-ls -f
docker exec pva-test pvcontrol graph ls
```

---

## Unix Socket Example

Demonstrates raw Unix domain socket proxying between containers.

**Provider** `pv-example-unix-server` — creates `/run/example/raw.sock`
**Consumer** `pv-example-unix-client` — expects socket at `/run/pv/services/raw.sock`

### Configuration

**Provider `services.json`:**
```json
[
  {"name": "raw", "type": "unix", "socket": "/run/example/raw.sock"}
]
```

**Consumer `args.json`:**
```json
{
  "PV_SERVICES_REQUIRED": [
    {"name": "raw", "target": "/run/pv/services/raw.sock"}
  ]
}
```

### Build and Verify

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-unix-server --target pv-example-unix-client
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-unix-*.pvrexport.tgz pvtx.d/
```

After containers start:
```bash
docker exec pva-test pvcontrol graph ls   # shows unix link
CLIENT_PID=$(docker exec pva-test lxc-info -n pv-example-unix-client -p | awk '{print $2}')
docker exec pva-test ls -la /proc/$CLIENT_PID/root/run/pv/services/   # injected socket
```

---

## REST Example

Demonstrates HTTP-over-UDS with identity header injection (`X-PV-Client`, `X-PV-Role`).

**Provider `services.json`:**
```json
[
  {"name": "api", "type": "rest", "socket": "/run/example/api.sock"}
]
```

**Consumer `args.json`:**
```json
{
  "PV_SERVICES_REQUIRED": [
    {"name": "api", "target": "/run/pv/services/api.sock"}
  ]
}
```

### Build

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-rest-server --target pv-example-rest-client
```

---

## D-Bus Example

Demonstrates policy-aware D-Bus proxying with role-to-UID mapping.

**Provider** runs a local `dbus-daemon` and Python service, publishing `org.pantavisor.Example`.

**Provider D-Bus policy (`org.pantavisor.Example.conf`):**
```xml
<busconfig>
  <policy user="root">
    <allow own="org.pantavisor.Example"/>
    <allow send_destination="org.pantavisor.Example"/>
  </policy>
  <policy context="default">
    <allow send_destination="org.pantavisor.Example"/>
  </policy>
</busconfig>
```

**Provider `services.json`:**
```json
[{"name": "system-bus", "type": "dbus", "socket": "/run/dbus/system_bus_socket"}]
```

**Consumer `args.json`:**
```json
{
  "PV_SERVICES_REQUIRED": [
    {
      "name": "system-bus",
      "type": "dbus",
      "interface": "org.pantavisor.Example",
      "target": "/run/dbus/system_bus_socket"
    }
  ]
}
```

### Build and Verify

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-dbus-server --target pv-example-dbus-client
```

Check client logs for successful D-Bus call:
```bash
docker exec pva-test tail -f /var/pantavisor/storage/logs/0/pv-example-dbus-client/lxc/console.log
# Expected: method return with org.pantavisor.Example response
```

---

## Hosted System Bus Example

Demonstrates the **pantavisor-hosted** D-Bus system bus: both provider and
consumer are single-pid containers — no `dbus-daemon`, policy XML or
`/etc/passwd` to ship. Pantavisor runs one shared bus (gated by the
`xconnect-dbus-systembus` build feature and the `xconnect.dbus.systembus.enabled`
config key, default on) and generates the bus policy from the manifests.

**Provider** (`pv-example-system-dbus-server`) declares the name it owns and the
caller roles allowed to reach it, in `services.json`:
```json
{
  "#spec": "service-manifest-xconnect@1",
  "services": [
    { "type": "dbus", "bus": "system-bus", "owns": "org.pantavisor.Example",
      "role": "example-service", "allow": ["operator", "monitor"] }
  ]
}
```

Provider and consumers attach to the bus with a `system-bus` requirement under
their role (provider as `example-service`, consumer as `operator`):
```json
{ "name": "system-bus", "type": "dbus", "role": "operator",
  "target": "/run/dbus/system_bus_socket" }
```

Two consumer containers demonstrate the allow list from both sides:
- `pv-example-system-dbus-client` attaches under the `operator` role, which is
  in the provider's `allow` list, so its calls are **permitted**.
- `pv-example-system-dbus-client-denied` attaches under the `stranger` role,
  which is **not** in the `allow` list, so the generated default-deny policy
  **refuses** its otherwise-identical calls.

### Policy Narrowing and Role UID Pinning

An `allow` entry may also be an object that narrows a role instead of granting
it full access to the owned name. `pv-avahi`
(`recipes-containers/pantavisor/pv-avahi/pv-avahi.services.json`) adds a third
`allow` entry, alongside the unchanged `"operator"`/`"monitor"` strings, for a
new `avahi-reader` role:
```json
{
  "role": "avahi-reader",
  "interfaces": ["org.freedesktop.Avahi.Server"],
  "members": ["GetVersionString"]
}
```

`interfaces`, `members` and `paths` are all optional and map one-to-one onto
the generated policy's `send_interface`, `send_member` and `send_path`
attributes:
```xml
<policy user="pv-dbus-avahi-reader">
  <allow send_destination="org.freedesktop.Avahi"
         send_interface="org.freedesktop.Avahi.Server"
         send_member="GetVersionString"/>
  <allow receive_sender="org.freedesktop.Avahi"/>
</policy>
```

:::note
`receive_sender` is never narrowed — replies and signals from the owner still
reach any allowed caller. Only the `send_*` side is restricted.
:::

A top-level `roles` map pins a role name to a real uid instead of one from
pantavisor's synthetic pool (base 90000). `pv-avahi` pins its own owner role:
```json
"roles": {
  "avahi-service": { "uid": 4242 }
}
```

Use a pin for a legacy daemon that authorizes callers via
`GetConnectionUnixUser` rather than the generated bus policy — it then sees
the pinned uid instead of one from the pool. Only a provider (a service that
declares an `owns` export) may pin a role; pins are device-wide by role name,
so two providers pinning the same role to different uids fails state
validation.

:::note
Never pin uid 0 to a role that a real caller also holds: `pv-xconnect`'s
ownership monitor authenticates as uid 0, so a uid-0 pin would make that
role's policy also match the monitor's own connection.
:::

`pv-example-system-dbus-reader`
(`recipes-containers/pv-examples/files/pv-example-system-dbus-reader.args.json`)
attaches under the narrowed `avahi-reader` role:
```json
{
  "PV_SERVICES_REQUIRED": [
    { "type": "dbus", "role": "avahi-reader", "names": ["org.freedesktop.Avahi"] }
  ]
}
```

Its allowed call succeeds; anything outside the narrowed interface/member is
refused by the generated policy:
```bash
docker exec -it pva-test pventer -c pv-example-system-dbus-reader \
    dbus-send --system --print-reply --dest=org.freedesktop.Avahi / \
    org.freedesktop.Avahi.Server.GetVersionString
# Expected: method return with the avahi-daemon version string

docker exec -it pva-test pventer -c pv-example-system-dbus-reader \
    dbus-send --system --print-reply --dest=org.freedesktop.Avahi / \
    org.freedesktop.Avahi.Server.GetHostName
# Expected: org.freedesktop.DBus.Error.AccessDenied — GetHostName is not in
# avahi-reader's narrowed member list
```

### Policy Fragments

An export's `policy` field names a raw D-Bus policy fragment, as a path
RELATIVE TO THE CONTAINER'S OWN TRAIL DIRECTORY. Pantavisor resolves it,
validates it, and splices it into the generated bus policy after the
generated rules. Where a JSON `allow` entry can only narrow to an
interface/member/path triple, a fragment can express anything `<policy>`,
`<allow>` and `<deny>` support — `send_path`, multiple rules per role, mixed
`allow`/`deny` — as long as it only touches that export's own `owns` name and
one of its own `allow` roles.

`pv-avahi` adds a fourth `allow` entry, `avahi-limited`, granted full access
by JSON, and narrows it down to "everything except `GetHostName`" with a
fragment:
```json
{
  "owns": "org.freedesktop.Avahi",
  "role": "avahi-service",
  "allow": ["operator", "monitor", { "role": "avahi-reader", "...": "..." }, "avahi-limited"],
  "policy": "dbus/avahi-policy.xml"
}
```

`recipes-containers/pantavisor/pv-avahi/avahi-policy.xml`:
```xml
<busconfig>
  <policy user="@role:avahi-limited@">
    <deny send_destination="org.freedesktop.Avahi"
          send_interface="org.freedesktop.Avahi.Server"
          send_member="GetHostName"/>
  </policy>
</busconfig>
```

`@role:avahi-limited@` is a placeholder pantavisor substitutes with the
role's masqueraded uid; a `<policy>` element may only ever key on
`user="@role:<name>@"` for a role already present in that same export's
`allow` list. The recipe ships the fragment via its
`PVR_APP_POST_FIXUP` hook (`container-pvrexport.bbclass`), which runs after
`pvr app add` and before signing:
```sh
install -d ${PN}/dbus
install -m 0644 ${WORKDIR}/avahi-policy.xml ${PN}/dbus/avahi-policy.xml
```
so on a running device the fragment is the file at
`/storage/trails/<rev>/pv-avahi/dbus/avahi-policy.xml`, the same path `pvr
device clone`/`pvr checkout` shows under `pv-avahi/dbus/avahi-policy.xml` in
a trail checkout.

`pv-example-system-dbus-limited`
(`recipes-containers/pv-examples/files/pv-example-system-dbus-limited.args.json`)
attaches under the narrowed `avahi-limited` role:
```json
{
  "PV_SERVICES_REQUIRED": [
    { "type": "dbus", "role": "avahi-limited", "names": ["org.freedesktop.Avahi"] }
  ]
}
```

:::note
JSON says WHO may call (which roles are in `allow`); a fragment may only
narrow HOW an already-allowed role calls, never grant access to a role
outside that `allow` list or to a name the export does not `own`.
:::

Validation rejects, and therefore rolls the deploy back on, a fragment that:
- contains any element other than `busconfig`, `policy`, `allow`, `deny`
  (`include`, `includedir`, `listen`, `type`, `auth`, `servicedir`, `limit`,
  `selinux`, `apparmor` are all refused);
- gives `<policy>` anything but `user="@role:<name>@"`, names a role that
  does not resolve, or names a role not in that export's own `allow` list;
- gives `<allow>`/`<deny>` anything but `send_*`/`receive_*`/`own`/
  `own_prefix` (`eavesdrop` is refused);
- has `own`/`own_prefix`/`send_destination`/`receive_sender` name anything
  other than one of that container's own `owns` names.

Four containers each exercise exactly one of these rejections:

| Container | `owns` | Fragment problem |
|-----------|--------|-------------------|
| `pv-example-system-dbus-badpolicy-include` | `org.pantavisor.BadInclude` | forbidden `<includedir>` element |
| `pv-example-system-dbus-badpolicy-foreign` | `org.pantavisor.BadForeign` | `<deny>` names `org.freedesktop.Avahi`, a name it does not own |
| `pv-example-system-dbus-badpolicy-role` | `org.pantavisor.BadRole` | `<policy>` references `@role:nosuchrole@`, which resolves to nothing |
| `pv-example-system-dbus-badpin` | none (`"services": []`) | pins a role uid (`roles: {"badpin-role": {"uid": 1234}}`) with no `owns` export on the platform — only a provider may pin a role uid |

None of the four ever runs a real D-Bus server; each is a busybox sleep loop
whose sole purpose is to fail state validation the moment its revision is
applied.

### Consumer `names` Form

A consumer can declare the well-known names it needs instead of hardcoding a
bus socket. Pantavisor derives `bus`, the link `name`, and `target` from each
name's owner; `role` stays required, since `allow` lists are written against
it:

```json
{
  "PV_SERVICES_REQUIRED": [
    { "type": "dbus", "role": "monitor", "names": ["org.freedesktop.Avahi"] }
  ]
}
```

`pv-avahi-browse` (`recipes-containers/pantavisor/pv-avahi-browse/args.json`)
uses exactly this to reach `pv-avahi`'s `org.freedesktop.Avahi`.

- Each entry in `names` must resolve to an export with a matching `owns` in
  the state; a name nobody owns fails validation.
- `target` defaults to `/run/dbus/system_bus_socket` for `system-bus`; only
  one entry per bus may take the default.
- A string element (`"org.freedesktop.Avahi"`) is shorthand for
  `{"name": "org.freedesktop.Avahi", "activation": {"mode": "none"}}`.

:::note
The legacy socket form (`name`, `type`, `role`, `target`, no `names`) keeps
working unchanged — use it for a provider-owned bus pantavisor knows nothing
about, as `pv-example-system-dbus-server`/`-client`/`-client-denied` above
still do.
:::

Check the resolved link with the device online:
```bash
docker exec pva-test pvcontrol graph ls
# Expected: a "consumes": "org.freedesktop.Avahi" entry for pv-avahi-browse
```

### Build and Verify

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-system-dbus-server --target pv-example-system-dbus-client \
    --target pv-example-system-dbus-client-denied
```

Pantavisor allocates a stable UID per role, generates the per-role allow
policy under `/run/pv/dbus/policy.d` on top of the daemon's default-deny base
config, and the proxy masquerades each connection to its role UID. Check the
consumer logs for a successful call:
```bash
docker exec pva-test tail -f /var/pantavisor/storage/logs/0/pv-example-system-dbus-client/lxc/console.log
# Expected: method return with org.pantavisor.Example response
```

A container requesting a role not in the `allow` list is denied by the generated
policy (`AccessDenied`), and a state that exports the reserved `system-bus` name
or double-owns a well-known name is rejected at validation. A `names` entry
that names nobody in the state is rejected the same way, before any container
runs — `pv-example-system-dbus-names-orphan` names `org.pantavisor.NoSuchService`
purely to exercise this negative path.

---

## DRM Example

Demonstrates DRM device node injection for graphics access.

**Provider** `pv-example-drm-provider` — exports DRM devices
**Consumer** `pv-example-drm-master` — requests `/dev/dri/card0` (KMS)
**Consumer** `pv-example-drm-render` — requests `/dev/dri/renderD128` (GPU rendering)

**Provider `services.json`:**
```json
[
  {"name": "drm-master", "type": "drm", "socket": "/dev/dri/card0"},
  {"name": "drm-render", "type": "drm", "socket": "/dev/dri/renderD128"}
]
```

**Consumer `args.json` (drm-master):**
```json
{
  "PV_SERVICES_REQUIRED": [{"name": "drm-master", "target": "/dev/dri/card0"}]
}
```

### Testing with VKMS

```bash
sudo modprobe vkms
ls -la /dev/dri/   # card0 (VKMS does not create renderD* nodes)
```

| Device | VKMS | Use case |
|--------|------|----------|
| `/dev/dri/card0` | Yes | KMS/display |
| `/dev/dri/renderD128` | No | GPU compute |

### Build and Run

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-drm-provider --target pv-example-drm-master
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-drm-*.pvrexport.tgz pvtx.d/

# Run with DRM device passthrough
docker run --name pva-test -d --privileged \
    --device /dev/dri:/dev/dri \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"
```

Verify injection:
```bash
MASTER_PID=$(docker exec pva-test lxc-info -n pv-example-drm-master -p | awk '{print $2}')
docker exec pva-test ls -la /proc/$MASTER_PID/root/dev/dri/   # expect card0 226:0
```

---

## Wayland Example

Demonstrates Wayland compositor access. Requires DRM.

**Provider** `pv-example-wayland-server` — Weston compositor (requires DRM from drm-provider)
**Consumer** `pv-example-wayland-client` — Wayland client

**Provider `services.json`:**
```json
[{"name": "wayland-0", "type": "wayland", "socket": "/run/wayland/wayland-0"}]
```

**Provider `args.json` (requires DRM):**
```json
{
  "PV_SERVICES_REQUIRED": [{"name": "drm-master", "target": "/dev/dri/card0"}]
}
```

**Consumer `args.json`:**
```json
{
  "PV_SERVICES_REQUIRED": [{"name": "wayland-0", "target": "/run/wayland/wayland-0"}]
}
```

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-drm-provider \
    --target pv-example-wayland-server \
    --target pv-example-wayland-client
```

> VKMS provides `card0` but won't produce actual display output. Full Wayland testing requires real GPU hardware.

---

## Debugging Tips

```bash
# Container status
docker exec pva-test lxc-ls -f

# Enter a container
docker exec -it pva-test pventer -c <container_name>

# Container namespace inspection
docker exec pva-test lxc-info -n <container_name> -p
docker exec pva-test ls -la /proc/<PID>/root/run/

# Common issues
```

| Symptom | Cause | Fix |
|---------|-------|-----|
| Container exits immediately | Missing DRM device | Add `--device /dev/dri:/dev/dri` |
| Socket not injected | pv-xconnect not running | `docker exec pva-test pvcontrol daemons ls` |
| "Connection refused" | Provider not ready | Wait for provider container RUNNING status |
| Device not found | Wrong major:minor | `stat /dev/dri/card0` on host |

```bash
# Cleanup between tests
docker rm -f pva-test
docker volume rm storage-test
```
