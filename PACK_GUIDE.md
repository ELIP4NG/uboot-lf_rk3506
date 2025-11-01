# U-Boot 打包指南

## 快速开始

### 完整构建并打包（推荐）
```bash
just pack-all
```
这会：
1. 编译 U-Boot
2. 打包成 4MB FIT 镜像 (uboot.img)
3. 包含 U-Boot + OP-TEE + DTB

### 仅打包（U-Boot 已编译）
```bash
just pack
# 或
just pack-fit
```

---

## 打包原理

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

### 文件组成

1. **u-boot-nodtb.bin**：主 U-Boot 程序（无 DTB）
2. **u-boot.dtb**：U-Boot 设备树
3. **tee.bin**：OP-TEE 安全固件（从 rkbin 提取）
4. **uboot.img**：最终 4MB FIT 镜像

---

## 镜像内容

生成的 `uboot.img` 包含：

| 组件 | 大小 | 加载地址 | 说明 |
|------|------|----------|------|
| U-Boot | ~653 KB | 0x00200000 | 主启动加载器 |
| OP-TEE | ~123 KB | 0x00001000 | 安全执行环境 |
| DTB | ~6 KB | - | 设备树 |
| Padding | ~3 MB | - | 填充到 4MB |

---

## 烧写方法

### 方法 1：使用 upgrade_tool（推荐）
```bash
# 进入 LOADER 模式
sudo upgrade_tool ld

# 烧写 U-Boot 分区
sudo upgrade_tool di -uboot uboot.img

# 或完整烧写
sudo upgrade_tool uf firmware.img  # firmware.img 包含所有分区
```

### 方法 2：使用 rkdeveloptool
```bash
# 进入 MASKROM 模式
sudo rkdeveloptool db ../rkbin/bin/rk35/rk3506b_ddr_750MHz_v1.06.bin

# 写入 U-Boot 分区（偏移根据分区表）
sudo rkdeveloptool wl 0x4000 uboot.img

# 重启
sudo rkdeveloptool rd
```

### 方法 3：手动 dd（已启动系统）
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

---

## 配置文件

### rkbin 配置

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

### 修改 Trust 版本
如需使用不同版本的 OP-TEE，修改 justfile：
```makefile
ini_trust := rkbin_dir / "RKTRUST/RK3506TOS_TA.ini"  # 使用 TA 版本
```

---

## 高级打包

### 分步打包（调试用）

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

### 问题 1：mkimage 命令未找到
```bash
# 确认 rkbin 工具存在
ls -lh ../rkbin/tools/mkimage

# 或使用系统 mkimage（需支持 FIT）
apt-get install u-boot-tools
```

### 问题 2：tee.bin 不存在
```bash
# 检查 rkbin 二进制
ls -lh ../rkbin/bin/rk35/rk3506_tee_v2.10.bin

# 更新 ini_trust 路径
```

### 问题 3：生成的 uboot.img 过小
```bash
# 检查是否填充到 4MB
ls -lh uboot.img

# 手动填充
truncate -s 4M uboot.img
```

### 问题 4：烧写后无法启动
- 检查分区表：U-Boot 分区偏移是否正确
- 检查 DDR 初始化：确认 SPL/DRAM 固件匹配硬件
- 查看串口日志：U-Boot 启动信息

---

## 与原厂镜像对比

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

## 参考资料

- [Rockchip U-Boot 文档](https://github.com/rockchip-linux/u-boot)
- [FIT Image 格式](https://github.com/u-boot/u-boot/blob/master/doc/uImage.FIT/howto.txt)
- [rkbin 仓库](https://github.com/rockchip-linux/rkbin)

---

## 许可证

与 U-Boot 和 rkbin 项目相同，遵循 GPL-2.0+ 许可证。
