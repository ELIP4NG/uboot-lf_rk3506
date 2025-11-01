# U-Boot 构建工具和打包文档

本文档整合了 U-Boot 构建、配置、打包和烧写的所有相关内容，包括自动启动设置、FIT 镜像打包和烧录方法。

---

## 📑 目录

1. [快速开始](#快速开始)
2. [构建命令参考](#构建命令参考)
3. [自动启动配置](#自动启动配置)
4. [打包指南](#打包指南)
5. [烧录方法](#烧录方法)
6. [配置和调试](#配置和调试)
7. [故障排除](#故障排除)
8. [技术参考](#技术参考)

---

## 快速开始

### 最常用的三个命令

```bash
# 1. 编译构建
just build

# 2. 完整重新编译（仅在需要重置配置时）
just from-scratch

# 3. 构建并打包（生成可烧录的 uboot.img）
just pack-all
```

---

## 构建命令参考

### 基础编译

| 命令 | 说明 |
|------|------|
| `just build` | 增量编译（保留 .config，推荐日常使用） |
| `just from-scratch` | 完全重新编译（会重置 .config） |
| `just clean` | 清理编译输出（保留 .config） |
| `just mrproper` | 深度清理（移除 .config 和所有输出） |

### 配置管理

| 命令 | 说明 |
|------|------|
| `just defcfg` | 使用默认配置重新配置 |
| `just menuconfig` | 打开交互式配置编辑器 |
| `just savedefconfig` | 保存当前配置到 defconfig |
| `just check` | 检查编译输出的二进制文件 |
| `just version` | 显示 U-Boot 版本 |

### 打包命令

| 命令 | 说明 |
|------|------|
| `just pack-all` | 构建并打包成 FIT 镜像（**推荐**） |
| `just pack` | 仅打包 FIT 镜像（U-Boot 需已编译） |
| `just pack-fit` | 生成 FIT 镜像并填充至 4MB |
| `just pack-uboot` | 仅打包 U-Boot 镜像 |
| `just pack-trust` | 仅打包 Trust/OP-TEE 镜像 |

---

## 自动启动配置

### 概述

本 U-Boot 已配置为自动从 eMMC 分区加载并执行纯文本格式的 `boot.cmd` 启动脚本。这采用了 Rockchip `script` 命令，无需编译脚本，便于直接编辑。

### 配置修改

#### 1. 环境变量设置 (`include/configs/rk3506_common.h`)

添加了以下自定义启动配置：

```c
#define CONFIG_EXTRA_ENV_SETTINGS \
    ENV_MEM_LAYOUT_SETTINGS \
    "boot_script=boot.cmd\0" \
    "bootdelay=1\0" \
    "load_boot_script=" \
        "echo Searching for ${boot_script} on mmc 0:2...; " \
        "if fatload mmc 0:2 ${scriptaddr} ${boot_script}; then " \
            "echo Loaded ${boot_script} from eMMC partition 2; " \
        "else " \
            "echo Failed to load ${boot_script}; " \
            "false; " \
        "fi\0" \
    "run_boot_script=" \
        "if script ${scriptaddr}; then " \
            "echo Boot script executed successfully; " \
        "else " \
            "echo Boot script execution failed; " \
        "fi\0" \
    "bootcmd=run load_boot_script run_boot_script\0" \
    ...
```

#### 2. 启动延迟调整 (`configs/rk3506_luckfox_defconfig`)

```
CONFIG_BOOTDELAY=1  # 从 0 改为 1 秒，允许查看启动信息
```

### 启动流程

1. **U-Boot 初始化** (1秒延迟)
2. **加载脚本**: 从 `mmc 0:2` (eMMC 第2分区，VFAT格式) 加载 `boot.cmd`
   - 加载地址: `0x00b00000` (scriptaddr)
3. **执行脚本**: 使用 Rockchip `script` 命令执行纯文本脚本
4. **启动内核**: boot.cmd 中定义的内核启动流程

### 关键特性

#### 使用 `script` 命令（优雅方案）

- ✅ **纯文本格式**: `boot.cmd` 无需 `mkimage` 编译
- ✅ **易于编辑**: 直接修改文本文件，无需重新编译
- ✅ **Rockchip 原生支持**: `script` 命令是 Rockchip U-Boot 特有功能
- ✅ **无需 SOURCE 支持**: `CONFIG_CMD_SOURCE` 保持禁用状态

#### vs. `source` 命令（标准方案）

标准 U-Boot 使用 `source` 命令，需要：
- ❌ 编译脚本: `mkimage -T script -C none -n 'boot script' -d boot.cmd boot.scr`
- ❌ 二进制格式: `.scr` 文件不可直接编辑
- ❌ 需要启用: `CONFIG_CMD_SOURCE=y`

### 内存布局

```
scriptaddr    = 0x00b00000  # boot.cmd 加载地址
kernel_addr_r = 0x00108000  # 内核加载地址（U-Boot 默认）
fdt_addr_r    = 0x00063000  # DTB 加载地址（U-Boot 默认）
ramdisk_addr_r= 0x01800000  # initramfs 加载地址（U-Boot 默认）
```

**注意**：`boot.cmd` 中使用的地址与 U-Boot 默认地址不同：
- kernel: `0x0c008000` (boot.cmd) vs `0x00108000` (U-Boot)
- fdt:    `0x0a200000` (boot.cmd) vs `0x00063000` (U-Boot)

### boot.cmd 内容

位置: `/embed/ELIP4NG/RK3506/luckfox_3506/boot/fs/boot.cmd`

```bash
echo "=== Starting RK3506 Luckfox Boot Sequence ==="

# 加载设备树
echo "Loading device tree..."
fatload mmc 0:2 0x0a200000 rk3506-luckfox.dtb

# 加载内核
echo "Loading kernel..."
fatload mmc 0:2 0x0c008000 zImage

# 加载 initramfs
echo "Loading initramfs..."
fatload mmc 0:2 0x0e000000 initrd

# 加载环境参数
echo "Loading environment..."
fatload mmc 0:2 0x0c100000 boot.env
env import -t 0x0c100000 ${filesize}

# 启动内核
echo "Booting kernel..."
bootz 0x0c008000 0x0e000000:${filesize} 0x0a200000
```

---

## 打包指南

### 什么是 FIT (Flattened Image Tree)？

- Rockchip 新一代固件格式
- 支持多 payload：U-Boot、Trust/OP-TEE、MCU、DTB 等
- 基于设备树（Device Tree）格式

### 打包流程

```
u-boot-nodtb.bin (653KB) ─┐
u-boot.dtb (6KB)          ├──> mkimage ──> uboot.img (4MB FIT)
tee.bin (123KB, OP-TEE)   ─┘
```

### 一键打包命令

在 `uboot/` 目录下：

```bash
just pack-all      # 构建并打包（推荐）
```

或

```bash
just pack-fit      # 仅打包（U-Boot 需已编译）
```

生成的 `uboot.img` 即为可直接烧录的 4MB 启动分区镜像。

### 文件组成

1. **u-boot-nodtb.bin**：主 U-Boot 程序（无 DTB）
2. **u-boot.dtb**：U-Boot 设备树
3. **tee.bin**：OP-TEE 安全固件（从 rkbin 提取）
4. **uboot.img**：最终 4MB FIT 镜像

### 镜像结构说明

- **FIT 格式**，包含：
  - U-Boot 主体（u-boot-nodtb.bin，入口/加载地址 0x00200000）
  - OP-TEE Trust 固件（tee.bin，入口/加载地址 0x00001000）
  - U-Boot DTB（u-boot.dtb）
- 镜像自动填充至 4MB，适配 eMMC 启动分区
- 入口点、os 类型、load/entry 属性与原厂一致

### 镜像内容

生成的 `uboot.img` 包含：

| 组件 | 大小 | 加载地址 | 说明 |
|------|------|----------|------|
| U-Boot | ~653 KB | 0x00200000 | 主启动加载器 |
| OP-TEE | ~123 KB | 0x00001000 | 安全执行环境 |
| DTB | ~6 KB | - | 设备树 |
| Padding | ~3 MB | - | 填充到 4MB |

### 与原厂镜像对比

| 项目 | 原厂 (uboot-part-ref.img) | 自编译 (uboot.img) |
|------|---------------------------|---------------------|
| 大小 | 4.0 MB | 4.0 MB |
| 格式 | FIT | FIT |
| U-Boot | ~653 KB | ~653 KB |
| OP-TEE | ~123 KB (v2.10) | ~123 KB (v2.10) |
| DTB | ~6 KB | ~6 KB |
| 兼容性 | ✓ | ✓ |

**结论**：自编译镜像与原厂镜像**结构一致**，可直接替换烧写。

---

## 烧录方法

### 方法 1：upgrade_tool（推荐）

```bash
# 进入 LOADER 模式
sudo upgrade_tool ld

# 烧写 U-Boot 分区
sudo upgrade_tool di -uboot uboot.img

# 或完整烧写
sudo upgrade_tool uf firmware.img  # firmware.img 包含所有分区
```

### 方法 2：rkdeveloptool

```bash
# 进入 MASKROM 模式
sudo rkdeveloptool db ../rkbin/bin/rk35/rk3506b_ddr_750MHz_v1.06.bin

# 写入 U-Boot 分区（偏移根据分区表）
sudo rkdeveloptool wl 0x4000 uboot.img

# 重启
sudo rkdeveloptool rd
```

### 方法 3：dd（已启动系统）

```bash
# 查看 U-Boot 分区
lsblk
# 假设 U-Boot 在 /dev/mmcblk0p1

# 烧写
sudo dd if=uboot.img of=/dev/mmcblk0p1 bs=1M

# 或直接写入 eMMC 偏移
sudo dd if=uboot.img of=/dev/mmcblk0 seek=16384 bs=512
```

> ⚠️ **警告**：dd 命令可能覆盖数据，请确认偏移地址和设备节点！

### 编译、打包和烧写的完整流程

```bash
# 1. 编译 U-Boot
cd /embed/ELIP4NG/RK3506/luckfox_3506/uboot
just from-scratch  # 完整重新编译

# 2. 生成的文件
# u-boot.img        882K  # 主镜像（包含 DTB）
# u-boot-dtb.img    882K  # DTB 镜像
# u-boot.bin        660K  # 原始二进制

# 3. 打包成 4MB FIT 镜像
just pack-fit

# 4. 烧写到 eMMC
sudo upgrade_tool di -uboot uboot.img

# 5. 准备 boot 分区（如需要）
cd ../boot
just build  # 生成 boot.vfat 镜像
sudo dd if=boot.vfat of=/dev/mmcblk0p2 bs=1M
```

---

## 配置和调试

### 查看 U-Boot 环境变量

进入 U-Boot 控制台：

```bash
# 打印所有环境变量
printenv

# 查看关键变量
printenv bootcmd
printenv boot_script
printenv scriptaddr
printenv load_boot_script
printenv run_boot_script
```

### 手动测试启动流程

```bash
# 1. 加载脚本
fatload mmc 0:2 ${scriptaddr} boot.cmd

# 2. 执行脚本
script ${scriptaddr}
```

### 调试输出

启动时会看到以下信息：

```
Searching for boot.cmd on mmc 0:2...
Loaded boot.cmd from eMMC partition 2
=== Starting RK3506 Luckfox Boot Sequence ===
Loading device tree...
Loading kernel...
Loading initramfs...
Loading environment...
Booting kernel...
```

### 配置文件

#### rkbin 配置

**Trust 配置**：`../rkbin/RKTRUST/RK3506TOS.ini`
```ini
[TOS]
TOSTA=bin/rk35/rk3506_tee_v2.10.bin
ADDR=0x1000
```

**Loader 配置**：`../rkbin/RKBOOT/RK3506BMINIALL.ini`
```ini
[CHIP_NAME]
NAME=RK350F

[LOADER_OPTION]
FlashData=bin/rk35/rk3506b_ddr_750MHz_v1.06.bin
FlashBoot=bin/rk35/rk3506_spl_v1.11.bin
```

#### 修改 Trust 版本

如需使用不同版本的 OP-TEE，修改 justfile：

```makefile
ini_trust := rkbin_dir / "RKTRUST/RK3506TOS_TA.ini"  # 使用 TA 版本
```

### 高级打包（分步打包）

```bash
# 1. 仅打包 U-Boot
just pack-uboot

# 2. 仅打包 Trust
just pack-trust

# 3. 手动合成 FIT（自定义 ITS）
# 编辑 uboot.its，然后：
../rkbin/tools/mkimage -f uboot.its -E uboot.img
```

### 自定义 FIT 配置

编辑 justfile 中的 `pack-fit` recipe，修改 `uboot.its` 内容：

```dts
/dts-v1/;
/ {
	description = "自定义描述";
	
	images {
		// 添加更多 payload，如 MCU 固件
		mcu {
			data = /incbin/("mcu.bin");
			type = "firmware";
			load = <0x08400000>;
		};
	};
};
```

---

## 故障排除

### boot.cmd 未找到

```
检查：
- eMMC 分区 2 是否格式化为 VFAT
- boot.cmd 是否存在于根目录
- 文件名是否正确（区分大小写）
```

### script 命令失败

```
可能原因：
- boot.cmd 语法错误
- 文件损坏或权限问题
- 内存地址冲突
```

### 内核启动失败

```
检查 boot.cmd 中：
- 文件路径是否正确
- 内存地址是否有效
- 内核镜像是否完整
```

### mkimage 命令未找到

```bash
# 确认 rkbin 工具存在
ls -lh ../rkbin/tools/mkimage

# 或使用系统 mkimage（需支持 FIT）
apt-get install u-boot-tools
```

### tee.bin 不存在

```bash
# 检查 rkbin 二进制
ls -lh ../rkbin/bin/rk35/rk3506_tee_v2.10.bin

# 更新 ini_trust 路径
```

### 生成的 uboot.img 过小

```bash
# 检查是否填充到 4MB
ls -lh uboot.img

# 手动填充
truncate -s 4M uboot.img
```

### 烧写后无法启动

- 检查分区表：U-Boot 分区偏移是否正确
- 检查 DDR 初始化：确认 SPL/DRAM 固件匹配硬件
- 查看串口日志：U-Boot 启动信息

### 恢复原始 U-Boot

```bash
# 从 SDK 恢复
cd /embed/ELIP4NG/RK3506/luckfox_3506/SDK/sdk/bin
sudo upgrade_tool di -uboot uboot.img
```

---

## 技术参考

### Rockchip `script` vs 标准 `source`

| 特性 | script (Rockchip) | source (标准) |
|------|-------------------|---------------|
| 格式 | 纯文本 | 编译二进制 (.scr) |
| 编辑 | 直接修改 | 需要 mkimage 重编译 |
| 配置要求 | CONFIG_CMD_SCRIPT_UPDATE | CONFIG_CMD_SOURCE |
| 文件扩展名 | .cmd / .txt | .scr / .scr.uimg |
| 可移植性 | Rockchip 特有 | 标准 U-Boot |

### 相关文件

```
uboot/
├── include/configs/rk3506_common.h    # 环境变量定义
├── configs/rk3506_luckfox_defconfig   # 配置选项
├── u-boot.img                          # 编译输出
├── BUILD_TOOL_DOCS.md                  # 本文档（集合所有构建/打包/烧录信息）
├── AUTO_BOOT_SETUP.md                  # 自动启动配置详情
└── justfile                            # 构建脚本

boot/
├── fs/boot.cmd                         # 启动脚本
├── boot.vfat                           # VFAT 镜像
└── justfile                            # 构建脚本
```

### 参考资源

- [Rockchip U-Boot 官方文档](https://github.com/rockchip-linux/u-boot)
- [FIT Image 格式说明](https://github.com/u-boot/u-boot/blob/master/doc/uImage.FIT/howto.txt)
- [rkbin 仓库](https://github.com/rockchip-linux/rkbin)

---

## 版本信息

- **验证日期**: 2025/11/01
- **硬件**: Luckfox Lyra RK3506B 开发板
- **U-Boot**: 基于 Lyra SDK
- **编译系统**: Just 任务运行器
- **打包格式**: FIT (Flattened Image Tree)

---

## 许可证

与 U-Boot 和 rkbin 项目相同，遵循 GPL-2.0+ 许可证。

---

**📌 建议**: 首先阅读[快速开始](#快速开始)和[构建命令参考](#构建命令参考)部分，快速上手日常开发。
