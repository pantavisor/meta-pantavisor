// SPDX-License-Identifier: MIT
//
// Exercise the CUDA driver API end to end: load libcuda, init, list the
// devices and create a context on each. nvidia-smi only proves NVML reaches the
// kernel module; this proves the CUDA path (GSP, UVM, JIT libraries) works.
//
// No cuda.h: the CUDA toolkit is not part of the build, so the few entry points
// used are declared here with the driver API's stable ABI.
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

typedef int CUresult;
typedef int CUdevice;
typedef void *CUcontext;

#define CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR 75
#define CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR 76

static CUresult (*cuInit)(unsigned int);
static CUresult (*cuDriverGetVersion)(int *);
static CUresult (*cuDeviceGetCount)(int *);
static CUresult (*cuDeviceGet)(CUdevice *, int);
static CUresult (*cuDeviceGetName)(char *, int, CUdevice);
static CUresult (*cuDeviceGetAttribute)(int *, int, CUdevice);
static CUresult (*cuDeviceTotalMem)(size_t *, CUdevice);
static CUresult (*cuCtxCreate)(CUcontext *, unsigned int, CUdevice);
static CUresult (*cuCtxDestroy)(CUcontext);
static CUresult (*cuGetErrorName)(CUresult, const char **);

static void *lib;

static void *sym(const char *name)
{
	void *p = dlsym(lib, name);

	if (!p) {
		fprintf(stderr, "cuda-probe: %s: %s\n", name, dlerror());
		exit(2);
	}
	return p;
}

static int check(CUresult r, const char *what)
{
	const char *name = "?";

	if (!r)
		return 0;
	cuGetErrorName(r, &name);
	fprintf(stderr, "cuda-probe: %s failed: %s (%d)\n", what, name, r);
	return 1;
}

int main(void)
{
	int version, count, i, failed = 0;

	lib = dlopen("libcuda.so.1", RTLD_NOW);
	if (!lib) {
		fprintf(stderr, "cuda-probe: %s\n", dlerror());
		return 2;
	}
	// The _v2 names are what cuda.h maps these to since CUDA 4.0/3.2.
	cuInit = sym("cuInit");
	cuDriverGetVersion = sym("cuDriverGetVersion");
	cuDeviceGetCount = sym("cuDeviceGetCount");
	cuDeviceGet = sym("cuDeviceGet");
	cuDeviceGetName = sym("cuDeviceGetName");
	cuDeviceGetAttribute = sym("cuDeviceGetAttribute");
	cuDeviceTotalMem = sym("cuDeviceTotalMem_v2");
	cuCtxCreate = sym("cuCtxCreate_v2");
	cuCtxDestroy = sym("cuCtxDestroy_v2");
	cuGetErrorName = sym("cuGetErrorName");

	if (check(cuInit(0), "cuInit"))
		return 1;
	if (check(cuDriverGetVersion(&version), "cuDriverGetVersion") ||
	    check(cuDeviceGetCount(&count), "cuDeviceGetCount"))
		return 1;
	printf("CUDA driver API %d.%d, %d device(s)\n", version / 1000,
	       (version % 1000) / 10, count);
	if (!count)
		return 1;

	for (i = 0; i < count; i++) {
		CUdevice dev;
		CUcontext ctx;
		char name[256];
		int major, minor;
		size_t mem;

		if (check(cuDeviceGet(&dev, i), "cuDeviceGet") ||
		    check(cuDeviceGetName(name, sizeof(name), dev),
			  "cuDeviceGetName") ||
		    check(cuDeviceGetAttribute(
				  &major,
				  CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR,
				  dev),
			  "cuDeviceGetAttribute") ||
		    check(cuDeviceGetAttribute(
				  &minor,
				  CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR,
				  dev),
			  "cuDeviceGetAttribute") ||
		    check(cuDeviceTotalMem(&mem, dev), "cuDeviceTotalMem")) {
			failed = 1;
			continue;
		}
		printf("  %d: %s, sm_%d%d, %zu MiB\n", i, name, major, minor,
		       mem >> 20);
		if (check(cuCtxCreate(&ctx, 0, dev), "cuCtxCreate")) {
			failed = 1;
			continue;
		}
		cuCtxDestroy(ctx);
	}

	return failed;
}
