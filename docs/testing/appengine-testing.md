# Appengine Testing

The appengine is a Docker-based environment for running and testing Pantavisor locally without real hardware.

## Load the Docker Image

```bash
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

## Prepare Test Containers

```bash
mkdir -p pvtx.d
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-*.pvrexport.tgz pvtx.d/
```

## Start Appengine

### Interactive Mode (recommended for development)

Gives manual control — start pantavisor when ready:

```bash
docker rm -f pva-test 2>/dev/null
docker volume rm storage-test 2>/dev/null

docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
```

### Auto Mode (simple testing)

```bash
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    pantavisor-appengine:latest
```

## Verify Startup

```bash
# Wait for READY (allow ~15–25s)
sleep 25

# Check build info
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/buildinfo

# Check containers are running
docker exec pva-test lxc-ls -f
```

## Device Passthrough (DRM/graphics testing)

```bash
docker run --name pva-test -d --privileged \
    --device /dev/dri:/dev/dri \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"
```

For VKMS (virtual DRM without real GPU):
```bash
sudo modprobe vkms
ls -la /dev/dri/   # should show card0
```

## Debugging

### Log Locations

| Log | Path |
|-----|------|
| Pantavisor | `/var/pantavisor/storage/logs/0/pantavisor/pantavisor.log` |
| Container Console | `/var/pantavisor/storage/logs/0/<container>/lxc/console.log` |
| LXC | `/var/pantavisor/storage/logs/0/<container>/lxc/lxc.log` |

> **Note**: In appengine, logs are at `/var/pantavisor/storage/logs/0/` rather than `/run/pantavisor/pv/logs/0/`.

```bash
# Tail pantavisor log
docker exec pva-test tail -f /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log

# Check container logs
docker exec pva-test cat /var/pantavisor/storage/logs/0/<container>/lxc/console.log
```

### Enter a Container Namespace

```bash
docker exec -it pva-test pventer -c <container_name>

# Or inspect the container rootfs directly
docker exec pva-test lxc-info -n <container_name> -p   # get PID
docker exec pva-test ls -la /proc/<PID>/root/
```

### API Testing

Use `pvcurl` (not `curl`) for the pv-ctrl socket:

```bash
# xconnect graph
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/xconnect-graph | jq .

# Container status
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/containers | jq .

# Daemon management
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/daemons | jq .
```

### pvcontrol CLI

```bash
# Container lifecycle
docker exec pva-test pvcontrol container ls
docker exec pva-test pvcontrol container stop <name>
docker exec pva-test pvcontrol container start <name>
docker exec pva-test pvcontrol container restart <name>

# Other
docker exec pva-test pvcontrol groups ls
docker exec pva-test pvcontrol graph ls
docker exec pva-test pvcontrol daemons ls
docker exec pva-test pvcontrol buildinfo
docker exec pva-test pvcontrol conf ls
```

For the full pv-ctrl API reference, see [pantavisor/docs/reference/pantavisor-commands.md](../../pantavisor/docs/reference/pantavisor-commands.md).

## Cleanup

### Between Tests

```bash
docker rm -f pva-test
docker volume rm storage-test
```

### Full Cleanup

```bash
docker rm -f pva-test
docker volume rm storage-test
docker rmi pantavisor-appengine:latest
# Remove all build artifacts (WARNING: slow to rebuild)
rm -rf build/tmp-scarthgap
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| pvtx.d not processed | Storage volume reused | `docker volume rm storage-test` |
| `pvcontrol` not found | Not in this image build | Use `pvcurl` directly |
| `curl` not found | Standard curl not in image | Use `pvcurl` (shell wrapper using nc) |
| Container crashes on xconnect start | Bad storage state | Fresh storage volume |
| `consumer_pid: 0` in xconnect-graph | Container not fully started | Wait for READY status |
| `path mismatch [1 link]` | Pseudo database corruption | `bitbake -c cleansstate <recipe>` |
| xconnect/pvcontrol/rngdaemon missing | `+=` used in distro include | Use `:append` for PANTAVISOR_FEATURES |

## Tips

- Always use `--max-time` with raw `curl` to avoid hangs
- Use `pvcurl` instead of `curl` for the pv-ctrl socket
- Interactive mode (`sleep infinity`) gives more control for debugging
- Rebuild AND reload the docker image after source changes
- Use `pvr inspect <pvrexport.tgz>` to verify container configuration before deploying
