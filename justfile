#!/usr/bin/env just --justfile

# U-Boot Build Configuration
cc_path := "/home/gcc-arm/gcc/bin/"
cross_compile_prefix := "arm-linux-gnueabihf-"
arch := "arm"
parallels := "24"
defconfig := "rk3506_luckfox_defconfig"

# Rockchip rkbin paths
rkbin_dir := "../rkbin"
rkbin_tools := rkbin_dir / "tools"
ini_trust := rkbin_dir / "RKTRUST/RK3506TOS.ini"
ini_loader := rkbin_dir / "RKBOOT/RK3506BMINIALL.ini"

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
# WARNING: This resets .config - use only when needed
defcfg:
	mkdir -p {{log_dir}}
	make ARCH={{arch}} CROSS_COMPILE={{cross_compile_prefix}} {{defconfig}} 2>&1 | tee {{log_file}}

# Build U-Boot (incremental - preserves .config)
# This is the normal daily build - does NOT reset configuration
build:
	mkdir -p {{log_dir}}
	make {{parallel_flag}} ARCH={{arch}} CROSS_COMPILE={{cross_compile_prefix}} 2>&1 | tee {{log_file}}

# Build from scratch: clean + defconfig + build
# WARNING: This will reset .config to defaults!
# Use this only when:
# - Setting up a new project
# - Resetting to default configurations
# - Troubleshooting build issues
from-scratch: mrproper defcfg build

# Clean (preserves .config)
clean:
	make clean

# Deep clean: removes .config and build artifacts (mrproper)
# WARNING: This resets .config!
mrproper:
	make mrproper

# Interactive configuration editor
# WARNING: This modifies .config - use with caution!
menuconfig:
	make ARCH={{arch}} CROSS_COMPILE={{cross_compile_prefix}} menuconfig

# Save defconfig
savedefconfig:
	make ARCH={{arch}} CROSS_COMPILE={{cross_compile_prefix}} savedefconfig
	@echo "To update: cp defconfig configs/{{defconfig}}"

# Check binaries
check:
	@ls -lh u-boot u-boot.bin 2>/dev/null || echo "No u-boot binaries found"

# Show version
version:
	@strings u-boot | grep "U-Boot 20" | head -1 || echo "U-Boot not built yet"

# ============================================================================
# Rockchip FIT Image Packaging
# ============================================================================

# Pack uboot.img (U-Boot FIT image with Trust/OP-TEE)
pack-uboot:
	#!/usr/bin/env bash
	set -e
	echo "=== Packing U-Boot FIT image ==="
	
	# Get load address from autoconf
	LOAD_ADDR=$(grep CONFIG_SYS_TEXT_BASE include/autoconf.mk | cut -d'=' -f2 | tr -d ' \r' || echo "0x00200000")
	echo "Load address: ${LOAD_ADDR}"
	
	# Pack U-Boot image
	{{rkbin_tools}}/loaderimage --pack --uboot u-boot-dtb.bin uboot.img ${LOAD_ADDR}
	
	echo "✓ Generated: uboot.img ($(du -h uboot.img | cut -f1))"
	ls -lh uboot.img

# Pack trust.img (Trust/OP-TEE image)
pack-trust:
	#!/usr/bin/env bash
	set -e
	echo "=== Packing Trust image ==="
	
	if [ ! -f {{ini_trust}} ]; then
		echo "ERROR: Trust INI not found: {{ini_trust}}"
		exit 1
	fi
	
	# Extract trust binary path from INI
	TRUST_BIN=$(grep "^TOSTA=" {{ini_trust}} | cut -d'=' -f2 | tr -d '\r')
	TRUST_ADDR=$(grep "^ADDR=" {{ini_trust}} | cut -d'=' -f2 | tr -d '\r')
	
	if [ -z "${TRUST_BIN}" ]; then
		echo "ERROR: No TOSTA in {{ini_trust}}"
		exit 1
	fi
	
	TRUST_PATH="{{rkbin_dir}}/${TRUST_BIN}"
	if [ ! -f "${TRUST_PATH}" ]; then
		echo "ERROR: Trust binary not found: ${TRUST_PATH}"
		exit 1
	fi
	
	echo "Trust binary: ${TRUST_BIN}"
	echo "Trust load address: ${TRUST_ADDR}"
	
	# Pack trust image
	{{rkbin_tools}}/loaderimage --pack --trustos "${TRUST_PATH}" trust.img ${TRUST_ADDR}
	
	echo "✓ Generated: trust.img ($(du -h trust.img | cut -f1))"
	ls -lh trust.img

# Pack FIT image combining U-Boot + Trust
pack-fit:
	#!/usr/bin/env bash
	set -e
	echo "=== Packing complete FIT image ==="
	
	if [ ! -f {{ini_trust}} ]; then
		echo "ERROR: Trust INI not found: {{ini_trust}}"
		exit 1
	fi
	
	# Get U-Boot load/entry address
	UBOOT_ADDR=$(grep CONFIG_SYS_TEXT_BASE include/autoconf.mk | cut -d'=' -f2 | tr -d ' \r' || echo "0x00200000")
	echo "U-Boot load/entry address: ${UBOOT_ADDR}"
	
	# Get OP-TEE address from INI
	OPTEE_ADDR=$(grep "^ADDR=" {{ini_trust}} | cut -d'=' -f2 | tr -d '\r' || echo "0x1000")
	echo "OP-TEE load/entry address: ${OPTEE_ADDR}"
	
	# Create temporary its file with correct entry points
	cat > uboot.its << EOF
	/dts-v1/;
	/ {
		description = "FIT Image with ATF/OP-TEE/U-Boot";
		#address-cells = <1>;
		
		images {
			uboot {
				description = "U-Boot";
				data = /incbin/("u-boot-nodtb.bin");
				type = "standalone";
				arch = "arm";
				os = "U-Boot";
				compression = "none";
				load = <${UBOOT_ADDR}>;
				entry = <${UBOOT_ADDR}>;
			};
			
			optee {
				description = "OP-TEE";
				data = /incbin/("tee.bin");
				type = "firmware";
				arch = "arm";
				os = "op-tee";
				compression = "none";
				load = <${OPTEE_ADDR}>;
				entry = <${OPTEE_ADDR}>;
			};
			
			fdt {
				description = "U-Boot dtb";
				data = /incbin/("u-boot.dtb");
				type = "flat_dt";
				arch = "arm";
				compression = "none";
			};
		};
		
		configurations {
			default = "conf";
			conf {
				description = "rk3506-luckfox";
				firmware = "optee";
				loadables = "uboot";
				fdt = "fdt";
			};
		};
	};
	EOF
	
	# Extract and prepare trust binary
	TRUST_BIN=$(grep "^TOSTA=" {{ini_trust}} | cut -d'=' -f2 | tr -d '\r')
	cp "{{rkbin_dir}}/${TRUST_BIN}" tee.bin
	
	# Generate FIT image
	{{rkbin_tools}}/mkimage -f uboot.its -E uboot.img
	
	# Pad to 4MB (typical eMMC partition size)
	truncate -s 4M uboot.img
	
	echo "✓ Generated: uboot.img (4MB, FIT format)"
	ls -lh uboot.img
	
	# Cleanup
	rm -f uboot.its tee.bin

# Pack all images (recommended for eMMC flashing)
pack-all: build pack-fit
	@echo ""
	@echo "=== All images packed ==="
	@echo "Ready to flash: uboot.img (4MB FIT image)"
	@ls -lh uboot.img 2>/dev/null || true

# Quick pack (just FIT, no rebuild)
pack: pack-fit
