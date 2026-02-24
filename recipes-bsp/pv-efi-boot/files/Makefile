# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT
#
# pv-efi-boot Makefile — gnu-efi freestanding cross-compilation
#
# Environment variables (set by Yocto recipe or caller):
#   GNUEFI_DIR  — gnu-efi sysroot (contains include/efi, lib, lib/gnuefi)
#   CC          — cross-compiler (e.g., x86_64-poky-linux-gcc)
#   LD          — linker (e.g., x86_64-poky-linux-ld)
#   OBJCOPY     — objcopy (e.g., x86_64-poky-linux-objcopy)
#   ARCH        — target arch (default: x86_64)

ARCH     ?= x86_64
GNUEFI_DIR ?= /usr

# gnu-efi paths — oe-core scarthgap installs everything under lib/
EFI_INC    = $(GNUEFI_DIR)/include/efi
EFI_INC_ARCH = $(EFI_INC)/$(ARCH)
EFI_LIB    = $(GNUEFI_DIR)/lib
EFI_LDS    = $(GNUEFI_DIR)/lib/elf_$(ARCH)_efi.lds

# Compiler flags for EFI freestanding
CFLAGS = -ffreestanding \
         -fno-stack-protector \
         -fpic \
         -fshort-wchar \
         -mno-red-zone \
         -Wall \
         -I$(EFI_INC) \
         -I$(EFI_INC_ARCH) \
         -DGNU_EFI_USE_MS_ABI \
         -DEFI_FUNCTION_WRAPPER

LDFLAGS = -nostdlib \
          -T $(EFI_LDS) \
          -shared \
          -Bsymbolic \
          -L$(EFI_LIB)

# Sections to keep in the EFI binary
OBJCOPY_SECTIONS = -j .text -j .sdata -j .data -j .rodata \
                   -j .dynamic -j .dynsym -j .rel -j .rela \
                   -j .rel.* -j .rela.* -j .reloc

# Common source files
COMMON_SRC = src/common/efivar.c src/common/autoboot.c src/common/partfind.c
COMMON_OBJ = $(COMMON_SRC:.c=.o)

# Targets
all: stage1.efi stage2.efi set-tryboot.efi

# Pattern rule for C -> object
%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Stage 1
STAGE1_OBJ = src/stage1/main.o $(COMMON_OBJ)

stage1.so: $(STAGE1_OBJ)
	$(LD) $(LDFLAGS) $(EFI_LIB)/crt0-efi-$(ARCH).o $^ -o $@ -lefi -lgnuefi

stage1.efi: stage1.so
	$(OBJCOPY) $(OBJCOPY_SECTIONS) --target efi-app-$(ARCH) $< $@

# Stage 2 (does not need common modules, only pvboot.h)
STAGE2_OBJ = src/stage2/main.o

stage2.so: $(STAGE2_OBJ)
	$(LD) $(LDFLAGS) $(EFI_LIB)/crt0-efi-$(ARCH).o $^ -o $@ -lefi -lgnuefi

stage2.efi: stage2.so
	$(OBJCOPY) $(OBJCOPY_SECTIONS) --target efi-app-$(ARCH) $< $@

# Test helper — sets PvTryBoot and chainloads stage1
TEST_OBJ = src/test/set-tryboot.o

set-tryboot.so: $(TEST_OBJ)
	$(LD) $(LDFLAGS) $(EFI_LIB)/crt0-efi-$(ARCH).o $^ -o $@ -lefi -lgnuefi

set-tryboot.efi: set-tryboot.so
	$(OBJCOPY) $(OBJCOPY_SECTIONS) --target efi-app-$(ARCH) $< $@

clean:
	rm -f $(STAGE1_OBJ) $(STAGE2_OBJ) $(TEST_OBJ) \
	      stage1.so stage2.so set-tryboot.so \
	      stage1.efi stage2.efi set-tryboot.efi

.PHONY: all clean
