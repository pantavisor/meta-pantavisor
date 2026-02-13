# Implementation Plan: Docker to PVR Converter Integration

## Overview
This plan implements Option 3: Direct Docker Archive Reference with automatic PVR conversion, eliminating manual Docker loading steps.

## Files to Modify

### 1. New Converter Recipe
**File**: `recipes-support/docker-to-pvr-converter/docker-to-pvr-converter_1.0.0.bb`
**Purpose**: Creates a utility that converts Docker archives to PVR repository format

### 2. Update Container Recipe  
**File**: `recipes-containers/images/flask-helloworld-container.bb`
**Addition**: Add `do_generate_pvr_archive()` task that:
- Depends on converter tool
- Runs converter after Docker image build
- Creates `flask-helloworld.pvr.tar.gz` PVR archive

### 3. Update Pantavisor Recipe
**File**: `recipes-containers/pantavisor/pv-flask-helloworld_1.0.0.bb`  
**Changes**:
- Remove `PVR_DOCKER_REF` (Docker registry reference)
- Add `PVR_SRC_URI = "file://flask-helloworld.pvr.tar.gz"` (PVR archive reference)
- Keep all existing configuration and arguments

## Build Workflow After Implementation

### Single Command Build
```bash
bitbake pv-flask-helloworld
```

### Automated Build Chain
1. **python3-flask-helloworld** → Builds Flask application package
2. **flask-helloworld-container** → Builds Docker image + PVR archive  
3. **docker-to-pvr-converter** → Creates conversion utility
4. **pv-flask-helloworld** → Uses PVR archive to create Pantavisor export

### Expected Output Artifacts
- `flask-helloworld-container-1.0-docker.tar` (Docker image)
- `flask-helloworld.pvr.tar.gz` (PVR repository)  
- `pv-flask-helloworld-1.0.0.pvrexport.tgz` (Pantavisor package)

## Benefits
- ✅ **Zero Manual Steps**: Single `bitbake` command builds everything
- ✅ **No Docker Daemon**: Pure Yocto/Pantavisor workflow
- ✅ **PVR Compatible**: Generates exact format Pantavisor expects
- ✅ **Cross Architecture**: Handles ARM64 builds on x86_64 hosts
- ✅ **Standard Yocto**: Uses native dependency mechanisms

## Implementation Steps
1. Create converter recipe utility
2. Update container recipe to auto-generate PVR archive
3. Update Pantavisor recipe to use PVR archive
4. Test complete build chain
5. Verify all artifacts are generated correctly

## Testing Strategy
- Build converter: `bitbake docker-to-pvr-converter`
- Build container with PVR: `bitbake flask-helloworld-container`
- Build full package: `bitbake pv-flask-helloworld`
- Verify PVR archive format and content
- Test complete automated workflow
