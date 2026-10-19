# 构建产物与上机验证记录（第二轮）

> 日期：2026-10-19 晚
> 目标：把第一轮留下的工程真正构建出可刷写产物，并在
> HTC Nexus 9（flounder / hboot 3.43.0.0114）上做引导验证。
> 设备序列号：HT4ARJT01614

本文档只记录**这一轮实际做了什么、看到了什么、结论是什么**。
硬件逆向资料见 [flounder-hboot-analysis.md](flounder-hboot-analysis.md)，
整体移植过程见 [porting-process.md](porting-process.md)。

---

## 0. 结论速览

| 项目 | 状态 |
|---|---|
| 内核 7.2.11 + flounder DTS 交叉编译 | ✅ |
| Android boot image v0（kernel+DTB+initramfs） | ✅ `out/boot.img`（22.7 MB） |
| 救援 boot image（`init=/bin/sh`） | ✅ `out/bootimg-rescue` |
| ext4 rootfs（NixOS 26.11 aarch64） | ✅ `out/rootfs.img`（4 GiB，实用 1.4 GiB，48 498 个文件） |
| 镜像结构自检 | ✅ `scripts/analyze-bootimg.py` |
| **hboot 实机引导** | ❌ 当前 7.2 Image 尚未被 hboot 成功引导（原因分析见第 4 节） |

**当前最重要的结论**：镜像本身格式正确（Android boot v0、gzip
Image、尾附 DTB、cmdline 正确），但 hboot 在引导前/早期就失败。
已经从实机行为中确认并修复了一个关键问题（nixpkgs 默认的
`CONFIG_EFI_ZBOOT=y` 让 `Image` 变成 EFI zboot，hboot 不是 EFI），
修复后仍未成功；目前最可疑的是 **7.2 Image 解压后 69 MB，覆盖了
hboot 固定放在 0x11000000 的 ramdisk**，以及 hboot 对
`kernel_addr`/`ramdisk_addr` 的处理方式。

---

## 1. 本轮修掉的问题

### 1.1 boot.img 的 cmdline 多了两个单引号

`nix/flounder-bootimg.nix` 原来写的是：

```nix
--cmdline "${lib.escapeShellArg cmdline}"
```

`escapeShellArg` 返回的是带单引号的字符串，放进双引号后单引号成了
字面量。实际写进 Android boot header 的 cmdline 变成：

```
'console=ttyS0,... root=/dev/mmcblk0p31 rw'
```

内核会把第一个参数解析成 `'console=...`，console/root 全部失效。
现已改为：

```nix
--cmdline ${lib.escapeShellArg cmdline}
```

并用 `scripts/analyze-bootimg.py` 验证 header 中不再有引号。

### 1.2 initramfs 里只有 busybox 和一个 sh 符号链接

原来只 `cp` 了 `${busybox}/bin/busybox`，但 `/init` 需要
`mount`、`sleep`、`switch_root`、`setsid` 等 applet。现在直接复制
busybox 的整个 `bin/` 和 `sbin/`（含相对 applet 符号链接），
`PATH` 改为 `/bin:/sbin`。当前 ramdisk 解压后约 3.4 MB，包含约
800 个 cpio 条目。

### 1.3 根文件系统在 initramfs 阶段看不到

内核 `.config` 里原来：

```
CONFIG_MMC_BLOCK=m
CONFIG_RPMB=m
CONFIG_CRYPTO_CRC32C=m
```

initrdless 启动时没有任何模块加载器，`/dev/mmcblk0p31` 不会出现，
ext4 也会因为缺 crc32c 挂不上。已在 `kernel/kernel-config.nix` 强制：

```
CONFIG_RPMB=y
CONFIG_MMC_BLOCK=y
CONFIG_MMC_BLOCK_MINORS=64   # GPT 有 33 个分区，默认 32 太小
CONFIG_CRYPTO_CRC32C=y
```

注意 `MMC_BLOCK` 的 Kconfig 依赖是 `RPMB || !RPMB`：当 `RPMB=m`
时 Kconfig 会把 `MMC_BLOCK` 的上限压到 `m`，所以必须同时把
`RPMB=y`，否则 configure 阶段会反复追问同一个问题并失败。

### 1.4 rootfs 镜像的属主和 Nix 数据库

- `mkfs.ext4 -d` 在 Nix sandbox 里以 nixbld 用户运行，直接打包会让
  `/nix/store` 里的文件属主变成构建用户。现在用 `fakeroot mkfs.ext4`
  （和 nixpkgs 的 `make-ext4-fs.nix` 一致）保证镜像内是 `root:root`。
- 镜像不是由 `nixos-install` 生成的，没有 Nix database。现在把
  `closureInfo/registration` 放到 `/nix-path-registration`，并新增
  `register-nix-paths.service`（首次启动执行 `nix-store --load-db`、
  `touch /etc/NIXOS`、`nix-env --set`），逻辑与 NixOS 的 SD 镜像模块一致。
- 去掉了错误的 `/bin/sh -> ${toplevel}/sw/bin/sh` 预置链接；`/bin/sh`
  由 NixOS activation 的 `binsh` 脚本创建。

### 1.5 nixpkgs 源码被塞进 rootfs（4.5 GiB）

第一次 rootfs 构建在 `mkfs.ext4` 前检查失败：

```
rootfs payload: 5800780280 bytes
ERROR: rootfs payload does not fit in 4G
```

原因是 NixOS 把 flake 的 `nixpkgs` input（本地 `path:` checkout）写进了
`/etc/nix/registry.json`，整个 nixpkgs 源码树（约 4.5 GiB）因此进入
系统闭包。移植不需要设备上的 nixpkgs registry，已在
`configuration/configuration.nix` 中：

```nix
nix.registry = lib.mkForce { };
```

之后闭包约 1.2 GiB，4 GiB 镜像有约 2.6 GiB 余量。rootfs 首启仍由
`x-systemd.growfs` 扩到 UDA 的 26 GiB。

### 1.6 `CONFIG_EFI_ZBOOT=y`（实机确认的关键问题）

nixpkgs 的 `common-config.nix` 对 aarch64 强制打开：

```nix
EFI_ZBOOT = lib.mkIf stdenv.hostPlatform.isAarch64 (whenAtLeast "6.1" yes);
```

它让 `arch/arm64/boot/Image` 变成 **EFI zboot 自解压 PE 镜像**，入口是
EFI stub。hboot 不是 EFI，它把解压后的 Image 当普通 arm64 Image 跳转，
于是执行到错误的入口。用 `scripts/analyze-bootimg.py` 可以看到修复前
Image 开头是：

```
4d 5a 40 fa ...   # "MZ" PE 头
```

而 pmOS/TWRP 的可用 Image 开头是：

```
1f 20 03 d5 ...   # NOP + branch
```

修复方式：`kernel/kernel-config.nix` 中强制关闭整个 EFI 路径：

```nix
EFI = force no;
EFI_STUB = force no;
EFI_ZBOOT = force no;
```

修复后 Image 开头恢复为 `1f 20 03 d5`（NOP），`code1` 是 branch，
`magic` 在 0x38 处为 `ARMd`，与 pmOS 一致。

### 1.7 构建时间/镜像体积的裁剪

第一版内核按 nixpkgs 默认配置编译所有 DRM/WiFi/音频/媒体模块，单次
内核构建约 1 小时，`Image` 解压后 69 MB。为了先让引导链跑通，本轮
在 `kernel-config.nix` 里关闭了本机不可能用到的子系统（AMDGPU、
Radeon、Nouveau、Tegra DRM、声卡、媒体、WLAN、蓝牙、InfiniBand、
ISDN、HAMRadio、STAGING、IIO 等），并关闭 BTF/调试信息相关选项的
计划见下一轮。当前 `Image` 仍然较大（约 69 MB），这是第 4 节问题的
直接原因。

---

## 2. 产物自检

所有检查都可以用仓库里的脚本复现：

```bash
scripts/analyze-bootimg.py out/boot.img
scripts/analyze-bootimg.py out/boot-highmem.img
```

当前 `out/boot.img` 的关键字段：

| 字段 | 值 |
|---|---|
| Android boot header | v0, pagesize 2048 |
| kernel | 21,053,221 bytes @ `0x20008000`（实际 0x90008000，见第 3.1/4 节） |
| ramdisk | 1,712,092 bytes @ `0x11000000`（hboot 默认值） |
| tags | `0x10000100` |
| cmdline | `earlycon=uart8250,mmio32,0x70006000 console=ttyS0,115200n8 console=tty0 no_console_suspend root=/dev/mmcblk0p31 rw` |
| 解压后 Image | 68,909,064 bytes，`code0=0xd503201f`（NOP），`code1=0x14bf443b`（branch） |
| 尾附 DTB | 44,803 bytes，magic `d00dfeed`，totalsize 44,803 |
| ramdisk | gzip -> 3,429,888 bytes，newc cpio |

rootfs 镜像自检（不依赖设备）：

```bash
dumpe2fs -h out/rootfs.img | grep -E 'volume name|Block count|Inode count'
e2fsck -fn out/rootfs.img
debugfs -R 'ls -l /' out/rootfs.img
debugfs -R 'stat /nix-path-registration' out/rootfs.img
```

结果：label `nixos-flounder`，4 GiB / 1 048 576 blocks，inode 524 288，
48 498 个文件，`e2fsck -fn` 干净；`/nix-path-registration` 0444
root:root；`/nix/var/nix/profiles/system` 和 `/init` 指向 store 里的
`nixos-system-flounder-26.11.20261019.dirty`。

内核配置中的启动关键项已逐条确认：

```
CONFIG_MMC_BLOCK=y
CONFIG_MMC_BLOCK_MINORS=64
CONFIG_RPMB=y
CONFIG_CRYPTO_CRC32C=y
CONFIG_EXT4_FS=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_TEGRA=y
CONFIG_SERIAL_EARLYCON=y
CONFIG_DRM_SIMPLEDRM=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_MMC_SDHCI_TEGRA=y
CONFIG_USB_XHCI_TEGRA=y
CONFIG_MFD_PALMAS=y
CONFIG_REGULATOR_PALMAS=y
```

---

## 3. 实机验证时间线（2026-10-19 下午/晚上）

设备在 fastboot 模式，`fastboot devices` 正常。

1. **第一次 `fastboot boot out/boot.img`（EFI_ZBOOT 修复前）**
   - 命令返回 `OKAY`，但设备在 8 s 内仍以 `18d1:4ee0` fastboot
     接口出现在 `lsusb`，USB 设备号不变。
   - 之后用 `fastboot boot hboot-analysis/twrp-flounder.img` 做对照，
     TWRP 正常启动并出现 `adb recovery`，证明 `fastboot boot` 本身可用。
2. **分析 Image 头**：发现 `Image` 以 `4d 5a 40 fa`（EFI zboot）开头，
   与 TWRP/pmOS 的 `1f 20 03 d5` 不同。定位到 `CONFIG_EFI_ZBOOT`。
3. **关闭 EFI 后重新构建**：`Image` 开头恢复为 NOP+branch。
   `fastboot boot` 仍然失败；设备保持 fastboot 接口 150 s 不变。
4. **尝试把 ramdisk 移到 0x15000000**（避免内核覆盖 ramdisk）：
   仍然失败。
5. **尝试直接 `fastboot flash boot out/boot.img` 后重启**：仍然回到
   fastboot；随后 `fastboot getvar` 开始超时，fastboot 接口不响应。
6. **对设备节点做 USBDEVFS_RESET**：设备从 USB 总线消失，之后没有
   重新枚举。需要人工断电/长按电源键复位（见第 5 节）。

> 注意：第 5 步已经把测试用的 `boot.img` 写进 LNX 分区。设备恢复后
> 第一件事应该是执行 `scripts/restore-boot.sh` 恢复
> `hboot-analysis/LNX.img`（原始 pmOS 镜像），再继续实验。

### 3.1 从实机 dump 得到的地址映射

`runtime-info.txt` 里下游内核的 `/proc/iomem` 给出了关键证据：

```
80000000-f5bfffff : System RAM
  80080000-80cd2023 : Kernel code
  80d46000-8102de1f : Kernel data
```

而 Android boot header 里写的是 `kernel_addr=0x10008000`，
`ramdisk_addr=0x11000000`。两者相差 `0x70000000`，说明 hboot 对
Tegra 的 DRAM 做了一个 `+0x70000000` 的地址别名/偏移：

- 内核实际加载在 `0x80008000`（代码从 `0x80080000` 开始）；
- ramdisk 实际在 `0x81000000`；
- 下游内核的 data 结束于 `0x8102de1f`，和 ramdisk 有约 188 KB
  的轻微重叠，但下游 3.10 Image 只有 19 MB，主体在 ramdisk 下方。

我们的 7.2 Image 解压后 69 MB，从 `0x80008000` 一直铺到
`0x84600000`，把 `0x81000000` 的 ramdisk 整段覆盖。这可以解释
为什么 hboot 跳转后系统没有任何可用输出/直接挂死。

---

## 4. 当前引导失败的假设与下一步实验

### 假设 A（最可能）：内核 Image 覆盖 ramdisk

7.2 Image 的 `image_size = 0x4380000`（70.8 MB）。无论 hboot 先加载
ramdisk 再解压内核，还是先解压内核再加载 ramdisk，`0x81000000`
处的 initramfs 都会被破坏。

实验产物：`out/boot.img`（默认）和 `out/boot-highmem.img`（同一布局）

```
kernel_addr   = 0x20008000   (实际 0x90008000，位于 ramdisk 上方)
ramdisk_addr  = 0x11000000   (实际 0x81000000，保持不变)
tags_addr     = 0x10000100
```

如果 hboot 尊重 boot header 的 `kernel_addr`，内核会被加载到
`0x90008000`，69 MB 的 Image 结束于 `0x94600000`，完全避开
`0x81000000` 的 ramdisk。测试命令：

```bash
scripts/test-boot-highmem.sh
# 等价于 fastboot boot out/boot-highmem.img
```

### 假设 B：hboot 不尊重 header 里的 load address

如果 A 仍然失败，需要用 TWRP 做对照实验：把 TWRP 的 `kernel_addr`
改到 `0x20008000`，看它是否还能启动；启动后 `adb shell cat
/proc/iomem | grep -A2 'System RAM'` 确认 Kernel code 的实际地址。
如果 TWRP 也不能在高地址启动，说明 hboot 固定使用
`0x10008000`，那就只能把内核做小。

### 假设 C：内核 Image 体积超过 hboot 的界限

如果 A/B 都失败，下一步是做一个 **明显更小的 Image**：

- `enableCommonConfig = false`，只用 arm64 defconfig + 本板需要的选项；
- 关闭 `DEBUG_INFO`/`DEBUG_INFO_BTF`/`KALLSYMS_ALL`/`FTRACE`/
  `KPROBES`/`BPF_SYSCALL`/`PERF_EVENTS`；
- 只保留 Tegra132、eMMC、ext4、serial、simpledrm、USB、PMIC、
  触摸/按键；
- 目标是把解压后 Image 压到 16 MB 以下（ramdisk 之前），
  或至少显著小于当前 69 MB。

### 假设 D：把 initramfs 直接编进内核

在 `kernel-config.nix` 里设置 `CONFIG_INITRAMFS_SOURCE` 指向
initramfs 目录，这样即使外部 ramdisk 被覆盖，内核也有内置 initramfs。
代价是要重新编译内核，且 boot.img 里仍要放一个合法的（可以很小的）
外部 ramdisk 以兼容 hboot。

---

## 5. 设备恢复

设备当前不在 USB 总线上（USBDEVFS_RESET 之后未重新枚举）。
请先**长按电源键 10–15 秒**强制断电，再按电源键开机；
开机后立刻按住 **音量下 + 电源** 进入 fastboot。

恢复原始 boot 分区（推荐先做）：

```bash
scripts/restore-boot.sh
# = fastboot flash boot hboot-analysis/LNX.img
```

如果 hboot 还能响应，也可以直接 `fastboot boot
hboot-analysis/twrp-flounder.img` 进 TWRP，再从 TWRP 里 dd 恢复：

```bash
adb shell "dd if=/dev/zero of=/dev/block/mmcblk0p16 bs=1M count=32"
adb push hboot-analysis/LNX.img /tmp/LNX.img
adb shell "dd if=/tmp/LNX.img of=/dev/block/mmcblk0p16 bs=1M"
adb shell sync
```

hboot 本体在 LNX 之外的裸区域，刷 boot 分区不会让设备变砖；
最坏情况也可以用 `fastboot boot twrp-flounder.img` 救回。

---

## 6. 复现构建

```bash
cd /home/lumiere/workspace/hboot-nixos

# 只构建 boot.img（内核已缓存时约 1 分钟）
NIX_MAX_JOBS=4 NIX_CORES=4 scripts/build-all.sh

# 或者单独构建实验镜像
nix --extra-experimental-features 'nix-command flakes' build .#bootimg-highmem
nix --extra-experimental-features 'nix-command flakes' build .#bootimg-rescue

# 结构检查
scripts/analyze-bootimg.py out/boot.img
```

`scripts/build-all.sh` 会把 `nix build` 的 store 符号链接复制成
`out/` 下的真实文件，避免 `nix-collect-garbage` 后产物消失；日志在
`out/logs/`。

---

## 7. 本轮产物清单

| 文件 | 说明 |
|---|---|
| `out/boot.img` | **默认** boot image：kernel @0x20008000，ramdisk @0x11000000（避开重叠） |
| `out/boot-highmem.img` | 与默认相同的实验布局（保留旧名字方便测试） |
| `out/bootimg-rescue` | `init=/bin/sh` 救援镜像 |
| `out/rootfs.img` | NixOS ext4 rootfs（4 GiB；1.4 GiB used；sha256 `c55dc996…0a9d6`） |
| `out/SHA256SUMS.txt` | 所有产物的 sha256 |
| `out/logs/*.log` | 本轮所有构建日志 |
| `scripts/analyze-bootimg.py` | boot image/Image/DTB/ramdisk 结构检查工具 |
| `scripts/restore-boot.sh` | 恢复原始 LNX 分区 |
| `scripts/test-boot-highmem.sh` | 测试高地址内核布局 |

> 由于设备在最后一次 USB 复位后离线，本轮没有拿到串口日志；
> 所有“实机行为”结论都来自 fastboot/USB 枚举状态和 Image 头分析。
> 下一次设备恢复后，优先测试默认的 `out/boot.img`（高地址布局），并在串口上抓
> `earlycon` 输出。
