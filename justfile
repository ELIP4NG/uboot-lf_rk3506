#!/usr/bin/env just --justfile

# U-Boot Build Configuration
cc_path := "/home/gcc-arm/gcc/bin/"
cross_compile_prefix := "arm-linux-gnueabihf-"
arch := "arm"
parallels := "24"
defconfig := "rk3506_luckfox_defconfig"

# Derived paths
jfdir := replace(justfile_directory(), "\\", "/")
cc_path_abs := if cc_path =~ "^/" { clean(cc_path) } else { clean(jfdir / cc_path) }
parallel_flag := "-j" + parallels
log_dir := jfdir / "logs"
log_file := log_dir / `date +'build-%Y%m%d-%H%M%S.log'`
origin_path := env_var("PATH")
new_path := cc_path_abs + ":" + origin_path

export PATH := new_path

# Show available commands
default:
	@just --list

# Configure with defconfig
defcfg:
	mkdir -p {{log_dir}}
	make ARCH={{arch}} CROSS_COMPILE={{cross_compile_prefix}} {{defconfig}} 2>&1 | tee {{log_file}}

# Build U-Boot
build:
	mkdir -p {{log_dir}}
	make {{parallel_flag}} ARCH={{arch}} CROSS_COMPILE={{cross_compile_prefix}} 2>&1 | tee {{log_file}}

# Full build
all: defcfg build

# Build from scratch
from-scratch: mrproper defcfg build

# Clean
clean:
	make clean

# Deep clean
mrproper:
	make mrproper

# Menuconfig
menuconfig:
	make ARCH={{arch}} CROSS_COMPILE={{cross_compile_prefix}} menuconfig

# Save defconfig
savedefconfig:
	make ARCH={{arch}} CROSS_COMPILE={{cross_compile_prefix}} savedefconfig
	@echo "To update: cp defconfig configs/{{defconfig}}"

# Check binaries
check:
	@ls -lh u-boot.bin u-boot 2>/dev/null || echo "No binaries"

# Show version
version:
	@grep "^VERSION\|^PATCHLEVEL\|^SUBLEVEL\|^EXTRAVERSION" Makefile | head -4
