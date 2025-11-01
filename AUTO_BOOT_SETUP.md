# U-Boot 自动启动配置

## 概述

本 U-Boot 已配置为自动从 eMMC 分区加载并执行纯文本格式的 `boot.cmd` 启动脚本。

## 配置修改

### 1. 环境变量设置 (`include/configs/rk3506_common.h`)

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

### 2. 启动延迟调整 (`configs/rk3506_luckfox_defconfig`)

```
CONFIG_BOOTDELAY=1  # 从 0 改为 1 秒，允许查看启动信息
```

## 启动流程

1. **U-Boot 初始化** (1秒延迟)
2. **加载脚本**: 从 `mmc 0:2` (eMMC 第2分区，VFAT格式) 加载 `boot.cmd`
   - 加载地址: `0x00b00000` (scriptaddr)
3. **执行脚本**: 使用 Rockchip `script` 命令执行纯文本脚本
4. **启动内核**: boot.cmd 中定义的内核启动流程

## 关键特性

### 使用 `script` 命令（优雅方案）

- ✅ **纯文本格式**: `boot.cmd` 无需 `mkimage` 编译
- ✅ **易于编辑**: 直接修改文本文件，无需重新编译
- ✅ **Rockchip 原生支持**: `script` 命令是 Rockchip U-Boot 特有功能
- ✅ **无需 SOURCE 支持**: `CONFIG_CMD_SOURCE` 保持禁用状态

### vs. `source` 命令（标准方案）

标准 U-Boot 使用 `source` 命令，需要：
- ❌ 编译脚本: `mkimage -T script -C none -n 'boot script' -d boot.cmd boot.scr`
- ❌ 二进制格式: `.scr` 文件不可直接编辑
- ❌ 需要启用: `CONFIG_CMD_SOURCE=y`

## 内存布局

```
scriptaddr    = 0x00b00000  # boot.cmd 加载地址
kernel_addr_r = 0x00108000  # 内核加载地址（U-Boot 默认）
fdt_addr_r    = 0x00063000  # DTB 加载地址（U-Boot 默认）
ramdisk_addr_r= 0x01800000  # initramfs 加载地址（U-Boot 默认）
```

注意：`boot.cmd` 中使用的地址与 U-Boot 默认地址不同：
- kernel: `0x0c008000` (boot.cmd) vs `0x00108000` (U-Boot)
- fdt:    `0x0a200000` (boot.cmd) vs `0x00063000` (U-Boot)

## boot.cmd 内容

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

## 编译和部署

### 1. 编译 U-Boot

```bash
cd /embed/ELIP4NG/RK3506/luckfox_3506/uboot
just from-scratch  # 完整重新编译
```

### 2. 生成的文件

```
u-boot.img        882K  # 主镜像（包含 DTB）
u-boot-dtb.img    882K  # DTB 镜像
u-boot.bin        660K  # 原始二进制
```

### 3. 烧写到 eMMC

**方法 1: 使用 Rockchip 工具**
```bash
# 使用 upgrade_tool 烧写到 uboot 分区
sudo upgrade_tool di -uboot u-boot.img
```

**方法 2: 使用 rkdeveloptool**
```bash
# 进入 MASKROM 模式
sudo rkdeveloptool db rkbin/bin/rk35/rk3506_ddr_*.bin
sudo rkdeveloptool wl 0x4000 u-boot.img  # 偏移地址根据分区表调整
```

**方法 3: 手动烧写（已启动系统）**
```bash
# 在设备上运行
dd if=u-boot.img of=/dev/mmcblk0 seek=16384 bs=512  # seek值根据分区表
```

### 4. 准备 boot 分区

```bash
cd /embed/ELIP4NG/RK3506/luckfox_3506/boot
just build  # 生成 boot.vfat 镜像

# 烧写到 eMMC 分区 2
sudo dd if=boot.vfat of=/dev/mmcblk0p2 bs=1M
```

## 测试和调试

### 查看 U-Boot 环境变量

进入 U-Boot 控制台：
```
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

## 故障排除

### 1. boot.cmd 未找到
```
检查：
- eMMC 分区 2 是否格式化为 VFAT
- boot.cmd 是否存在于根目录
- 文件名是否正确（区分大小写）
```

### 2. script 命令失败
```
可能原因：
- boot.cmd 语法错误
- 文件损坏或权限问题
- 内存地址冲突
```

### 3. 内核启动失败
```
检查 boot.cmd 中：
- 文件路径是否正确
- 内存地址是否有效
- 内核镜像是否完整
```

### 4. 恢复原始 U-Boot
```bash
# 从 SDK 恢复
cd /embed/ELIP4NG/RK3506/luckfox_3506/SDK/sdk/bin
sudo upgrade_tool di -uboot uboot.img
```

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
└── AUTO_BOOT_SETUP.md                  # 本文档

boot/
├── fs/boot.cmd                         # 启动脚本
├── boot.vfat                           # VFAT 镜像
└── justfile                            # 构建脚本
```

## 许可证

与 U-Boot 项目相同，遵循 GPL-2.0+ 许可证。
