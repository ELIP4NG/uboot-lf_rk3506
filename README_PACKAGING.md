# RK3506 Luckfox U-Boot 打包与烧录说明

## 1. 打包流程概述

本工程已实现一键打包生成适用于 eMMC 烧录的 4MB FIT 格式 uboot.img，兼容原厂分区结构。

- 支持 U-Boot + OP-TEE (Trust) + DTB 多合一
- 完全兼容 Rockchip 官方烧录工具
- 入口点、加载地址等关键参数与原厂一致

---

## 2. 一键打包命令

在 `uboot/` 目录下：

```bash
just pack-all
```
或
```bash
just pack-fit
```

生成的 `uboot.img` 即为可直接烧录的 4MB 启动分区镜像。

---

## 3. 镜像结构说明

- **FIT 格式**，包含：
  - U-Boot 主体（u-boot-nodtb.bin，入口/加载地址 0x00200000）
  - OP-TEE Trust 固件（tee.bin，入口/加载地址 0x00001000）
  - U-Boot DTB（u-boot.dtb）
- 镜像自动填充至 4MB，适配 eMMC 启动分区
- 入口点、os 类型、load/entry 属性与原厂一致

---

## 4. 烧录方法

### 方式一：upgrade_tool
```bash
sudo upgrade_tool di -uboot uboot.img
```

### 方式二：rkdeveloptool
```bash
sudo rkdeveloptool wl 0x4000 uboot.img
```

### 方式三：dd（已启动系统）
```bash
sudo dd if=uboot.img of=/dev/mmcblk0p1 bs=1M
# 或
sudo dd if=uboot.img of=/dev/mmcblk0 seek=16384 bs=512
```

> ⚠️ 烧录前请确认分区偏移与原厂一致，避免覆盖数据。

---

## 5. 关键文件与配置

- `uboot/justfile`：一键打包脚本，自动处理 entry/load 参数
- `rkbin/`：Rockchip 官方二进制与工具
- `rkbin/RKTRUST/RK3506TOS.ini`：Trust/OP-TEE 配置
- `rkbin/RKBOOT/RK3506BMINIALL.ini`：Loader 配置

---

## 6. 常见问题

- **烧录后无法启动**：请确认入口点、optee 地址、DTB 与原厂一致，建议用 justfile 自动打包
- **镜像过小**：justfile 已自动填充 4MB
- **OP-TEE/Trust 版本不兼容**：可在 ini_trust 路径切换不同版本

---

## 7. 参考
- [Rockchip U-Boot 官方文档](https://github.com/rockchip-linux/u-boot)
- [FIT Image 格式说明](https://github.com/u-boot/u-boot/blob/master/doc/uImage.FIT/howto.txt)
- [rkbin 工具链](https://github.com/rockchip-linux/rkbin)

---

## 8. 版本信息
- 本打包方案已在 2025/11/01 验证通过，兼容 Luckfox Lyra RK3506B 开发板。
