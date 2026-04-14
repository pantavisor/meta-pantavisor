# Pantavisor Development

Use `kas/with-workspace.yaml` to develop pantavisor source locally while rebuilding through the Yocto layer.

## Initial Setup

The first build with the workspace overlay creates the devtool workspace:

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml
```

Workspace sources:
```
build/workspace/sources/pantavisor/   # Pantavisor runtime
build/workspace/sources/lxc-pv/       # LXC with pantavisor patches
```

Workspace bbappend files (redirect recipes to local sources):
```
build/workspace/appends/pantavisor_git.bbappend
build/workspace/appends/lxc-pv_git.bbappend   # create manually if needed
```

## Development Cycle

1. **Edit source code**:
   ```bash
   cd build/workspace/sources/pantavisor
   # Make changes to C files, headers, etc.
   ```

2. **Rebuild**:
   ```bash
   cd /path/to/meta-pantavisor
   ./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml
   ```

3. **Test** — see [../testing/development-workflow.md](../testing/development-workflow.md)

4. **Commit when ready**:
   ```bash
   cd build/workspace/sources/pantavisor
   git add -A && git commit -m "feat: description" && git push
   ```

## Building Specific Targets

Build only pantavisor (faster iteration):
```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pantavisor
```

Build pantavisor and appengine image:
```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pantavisor-appengine
```

## Common Workflows

### Quick Pantavisor Change Test

```bash
# 1. Edit pantavisor source
cd build/workspace/sources/pantavisor
vim xconnect/plugins/drm.c

# 2. Rebuild (from meta-pantavisor root)
cd /path/to/meta-pantavisor
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml

# 3. Reload docker image
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar

# 4. Test (fresh storage)
docker rm -f pva-test; docker volume rm storage-test
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"
docker exec pva-test sh -c 'pv-appengine &'
sleep 15
docker exec pva-test lxc-ls -f
```

### Testing xconnect Plugin Changes

```bash
# 1. Edit plugin
cd build/workspace/sources/pantavisor
vim xconnect/plugins/unix.c

# 2. Build appengine
cd /path/to/meta-pantavisor
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml

# 3. Reload and test
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
docker rm -f pva-test; docker volume rm storage-test
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"
docker exec pva-test sh -c 'pv-appengine &'
sleep 15
docker exec pva-test pvcontrol graph ls
```

### Bumping pantavisor SRCREV

When updating `SRCREV` in `recipes-pv/pantavisor/pantavisor_git.bb`:

1. **Verify the hash against the actual remote** — squash merges rewrite hashes, so a branch SHA won't match the merged master SHA
2. **Update `PKGV`** to match the latest tag reachable from the new SRCREV (e.g. if latest tag is `026`, set `PKGV = "026+git0+${GITPKGV}"`)

## Adding Workspace Packages

To use a local source for a package not yet in the workspace (e.g., lxc-pv):

```bash
# Create bbappend
cat > build/workspace/appends/lxc-pv_git.bbappend << 'EOF'
inherit externalsrc
EXTERNALSRC = "${TOPDIR}/workspace/sources/lxc-pv"
EXTERNALSRC_BUILD = "${WORKDIR}/build"
EOF

# Clone the source
cd build/workspace/sources
git clone https://github.com/pantavisor/lxc.git lxc-pv
cd lxc-pv && git checkout <branch>
```

## Troubleshooting Build Issues

### Stale Build Artifacts

```bash
./kas-container shell .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    -c "bitbake -c cleansstate <recipe-name>"
```

### Stale Configure Artifacts in Workspace Source

```bash
cd build/workspace/sources/<package>
git clean -fdx
```

### Docker Image Not Updated

After rebuilding, always reload the docker image before testing:
```bash
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```
