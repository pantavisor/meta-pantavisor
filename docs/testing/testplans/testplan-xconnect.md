# xconnect Service Mesh Test Plan

Tests for pv-xconnect container-to-container communication via the appengine environment.

For pv-ctrl API tests (daemons, graph, metadata, objects, etc.), see [testplan-pvctrl.md](testplan-pvctrl.md).

---

## Prerequisites

### Build Appengine Image

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml

docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

> To test local pantavisor changes, build with the `:kas/with-workspace.yaml`
> overlay. `externalsrc` does not change task signatures, so force a fresh
> compile or sstate may serve a stale binary:
> `./kas-container shell <cfg>:kas/with-workspace.yaml -c "bitbake -c cleansstate pantavisor && bitbake pantavisor-appengine-distro"`

### Common Setup

```bash
docker rm -f pva-test 2>/dev/null
docker volume rm storage-test 2>/dev/null
mkdir -p pvtx.d
```

### Common Teardown

```bash
docker rm -f pva-test
docker volume rm storage-test
```

---

## Test 1: Unix Socket Service Mesh

**Purpose**: Verify pv-xconnect injects Unix sockets between provider and consumer containers.

### Setup

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-unix-server \
    --target pv-example-unix-client

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-unix-server.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-unix-client.pvrexport.tgz pvtx.d/
```

### Execute

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Verify

```bash
# Check both containers running
docker exec pva-test lxc-ls -f
# Expected: pv-example-unix-server RUNNING, pv-example-unix-client RUNNING

# Check xconnect graph
docker exec pva-test pvcontrol graph ls
# Expected: JSON with type=unix, consumer=pv-example-unix-client

# Check socket injected into consumer
CLIENT_PID=$(docker exec pva-test lxc-info -n pv-example-unix-client -p | awk '{print $2}')
docker exec pva-test ls -la /proc/$CLIENT_PID/root/run/pv/services/
# Expected: raw-unix.sock socket file
```

### Expected Results

| Check | Expected |
|-------|----------|
| Server status | RUNNING |
| Client status | RUNNING |
| xconnect graph | Shows unix link between server and client |
| Injected socket | `/run/pv/services/raw-unix.sock` exists in client |

---

## Test 2: D-Bus Service Mesh

**Purpose**: Verify pv-xconnect D-Bus proxy with role-to-UID mapping.

### Setup

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-dbus-server \
    --target pv-example-dbus-client

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-dbus-server.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-dbus-client.pvrexport.tgz pvtx.d/
```

### Execute

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Verify

```bash
# Check containers running
docker exec pva-test lxc-ls -f
# Expected: pv-example-dbus-server RUNNING, pv-example-dbus-client RUNNING

# Check xconnect graph
docker exec pva-test pvcontrol graph ls
# Expected: JSON with type=dbus link

# Check client logs for successful D-Bus call
docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-example-dbus-client/lxc/console.log | tail -20
# Expected: method return with org.pantavisor.Example response
```

### Expected Results

| Check | Expected |
|-------|----------|
| Server status | RUNNING |
| Client status | RUNNING |
| xconnect graph | Shows dbus link between server and client |
| D-Bus call | Successful method return in client logs |

---

## Test 3: REST Service Mesh

**Purpose**: Verify pv-xconnect proxies HTTP-over-Unix-socket between consumer and provider.

### Setup

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-rest-server \
    --target pv-example-rest-client

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-rest-server.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-rest-client.pvrexport.tgz pvtx.d/
```

### Execute

Same as Test 1 (run `pva-test`, start `pv-appengine`, wait).

### Verify

```bash
docker exec pva-test pvcontrol graph ls
# Expected: type=rest link (service network-manager)

docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-example-rest-client/lxc/console.log | tail -10
# Expected: JSON response body from the network-manager service
```

### Expected Results

| Check | Expected |
|-------|----------|
| Server / Client status | RUNNING |
| xconnect graph | Shows rest link |
| REST call | Client logs show provider's JSON response |

---

## Test 4: DRM Device Injection

**Purpose**: Verify pv-xconnect injects DRM device nodes into consumer containers.

**Note**: Requires VKMS kernel module or real GPU hardware. The `wayland`
plugin shares this teardown path; its example additionally requires a
`drm-master` provider, so deploy the DRM pair alongside it.

### Setup

```bash
# Load VKMS on host (if no real GPU)
sudo modprobe vkms

./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-drm-provider \
    --target pv-example-drm-master

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-drm-provider.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-drm-master.pvrexport.tgz pvtx.d/
```

### Execute

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    --device /dev/dri:/dev/dri \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Verify

```bash
# Check containers running
docker exec pva-test lxc-ls -f
# Expected: pv-example-drm-provider RUNNING, pv-example-drm-master RUNNING

# Check DRM device in consumer
MASTER_PID=$(docker exec pva-test lxc-info -n pv-example-drm-master -p | awk '{print $2}')
docker exec pva-test ls -la /proc/$MASTER_PID/root/dev/dri/
# Expected: card0 device node
```

### Expected Results

| Check | Expected |
|-------|----------|
| Provider status | RUNNING |
| Master status | RUNNING |
| DRM device | `/dev/dri/card0` exists in master container |

---

## Proxy Lifecycle Checks (unix / rest / dbus / wayland)

The stream proxies share one teardown path. These checks guard it against
two regressions: an fd leak when a provider holds its connection open after
the consumer leaves, and a truncated response when a client half-closes its
write side and then reads. Run against a live rest mesh (Test 3).

```bash
# Reach a consumer's injected socket from the host via /proc/<pid>/root
RPID=$(docker exec pva-test lxc-info -n pv-example-rest-client -p | awk '{print $2}')
SOCK=/proc/$RPID/root/run/pv/services/network-manager.sock
XPID=$(docker exec pva-test sh -c 'for p in /proc/[0-9]*; do
  grep -qa pv-xconnect "$p/cmdline" 2>/dev/null && { echo ${p##*/}; break; }; done')
```

**Normal request/response** — full body:
```bash
docker exec pva-test sh -c "printf 'GET /info HTTP/1.0\r\n\r\n' | nc -U $SOCK"
# Expected: HTTP/1.0 200 OK + JSON body
```

**Half-close** (`nc -N` shuts the write side then reads) — must still return
the full body:
```bash
docker exec pva-test sh -c "printf 'GET /info HTTP/1.0\r\n\r\n' | nc -N -U $SOCK"
# Expected: same full body. Empty output = the proxy tore the response path
# down on the client's EOF (regression; this is what pvcurl POST uses).
```

**No fd leak** — xconnect fds stay bounded under repeated connects:
```bash
docker exec pva-test sh -c "
  base=\$(ls /proc/$XPID/fd | wc -l); n=0
  while [ \$n -lt 100 ]; do n=\$((n+1))
    printf 'GET /info HTTP/1.0\r\n\r\n' | nc -N -U $SOCK >/dev/null 2>&1
  done
  echo \"fds: \$base -> \$(ls /proc/$XPID/fd | wc -l)\""
# Expected: end count near base, not base + 100. (A half-open session whose
# provider never closes is reclaimed after an inactivity linger, ~60s.)
```

### Expected Results

| Check | Expected |
|-------|----------|
| Normal request | Full HTTP response body |
| Half-close request | Same full body (not empty) |
| fd count after 100 connects | Bounded near baseline, not climbing |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| pvtx.d not processed | Storage volume reused | Delete volume: `docker volume rm storage-test` |
| Container not starting | Check pantavisor.log | `docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log` |
| xconnect-graph empty | pv-xconnect not running | `docker exec pva-test pvcontrol daemons ls` |
| Socket not injected | Provider not ready | Wait longer, check provider status |
| pantavisor restart loop | A platform's required service is missing (e.g. wayland needs `drm-master`) | Deploy the required provider, or omit that example |
