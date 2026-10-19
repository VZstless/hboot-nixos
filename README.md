# NixOS 26.11-unstable on the HTC Nexus 9 (flounder)

为 HTC Google Nexus 9（代号 **flounder**，NVIDIA Tegra132 / 双核 Denver，
arm64）适配 **NixOS 26.11-unstable**（nixpkgs master，2026-10）的完整工程。

```
引导链:  BootROM → xloader → hboot(HTC bootloader) → LNX 分区(Android boot image)
              └─ 内核: mainline Linux 7.2 (nixpkgs linux_latest, 交叉编译)
              └─ 设备树: 本仓库新增的 tegra132-flounder.dts (追加在内核镜像尾部)
              └─ initramfs: 自制 busybox 微型 initramfs (~2 MiB)
              └─ rootfs: UDA 分区 (/dev/mmcblk0p31, ext4, systemd-growfs 自动扩容)
```

## 当前状态（2026-10-19 深夜）

- ✅ **NixOS 26.11-unstable 已在真机（HT4ARJT01614）上启动成功。**
- ✅ 构建产物在 `out/`：`boot.img` 7.8 MB（15.2 MB 解压内核）、
  `rootfs.img` 4 GiB、`bootimg-rescue`、`SHA256SUMS.txt`。
- ✅ 关键结论：hboot 拒绝解压后超过 ~40 MiB 的内核；nixpkgs 默认
  7.2 内核是 69 MiB。现在使用 `enableCommonConfig = false` 的
  极小内核（15.2 MB），并关闭 Tegra132 上会挂死的 BPMP/IVC/SMMU。
- ✅ GPT 头在 LBA 69631（非标准位置），主线解析不到；initramfs 用
  `losetup -o 3737124864` 直接挂载 UDA（`fstab` 已改为 `/dev/loop0`）。
- ✅ rootfs 必须用 TWRP + `adb push` 逐字节写 4 GiB；`fastboot flash`
  的 sparse 写入会跳过零块，导致 ext4 位图损坏。
- ✅ 显示：DTB 里给 simplefb 加了 `dsi/lcd/io-supply`，并让
  `avdd-lcd`/`iovdd-lcd` `always-on`，避免启动后黑屏。

### 怎么在设备上输入命令

平板的 micro-USB 现在是 **USB host**，电脑端不会出现 adb/串口。三种方式：

1. **USB OTG 转接头 + USB 键盘**（最简单）：插上后按 Enter，
   tty1 已配置 `root` 自动登录，应直接出现 `[root@flounder:~]#`。
2. **UART 串口**：主板测试点 TX/RX/GND，115200 8N1；登录用户
   `root`，密码 `flounder`。
3. **网络**：WiFi 还缺 BCM4354 固件/NVRAM；USB 网卡驱动也未编译，
   所以暂时不能 SSH。

登录后可以运行 `nixos-version`、`ip a`、`dmesg`、`lsblk` 等。
`/` 显示为 `/dev/loop0` 是正常的（绕过了 hboot 的非标准 GPT 位置）。

## 目录结构

| 路径 | 内容 |
|---|---|
| `flake.nix` | flake 入口（nixpkgs = 本地 26.11-unstable checkout） |
| `configuration/configuration.nix` | NixOS 系统配置（用户/服务/软件） |
| `configuration/flounder-hardware.nix` | 硬件模块：内核、boot 链、rootfs 镜像 |
| `kernel/dts/tegra132-flounder.dts` | **新写的主线风格设备树**（本移植的核心） |
| `kernel/0001-arm64-dts-nvidia-Add-support-for-the-HTC-Nexus-9-flounder.patch` | 上述 DTS 的内核补丁 |
| `kernel/kernel-config.nix` | 内核配置片段（structuredExtraConfig） |
| `nix/flounder-initramfs.nix` + `nix/flounder-init.sh` | 微型 busybox initramfs |
| `nix/flounder-bootimg.nix` | Android boot image 组装（mkbootimg 参数见注释） |
| `nix/flounder-rootfs.nix` | ext4 rootfs 镜像（mkfs.ext4 -d + closureInfo） |
| `scripts/` | 构建、刷机、恢复与 boot.img 分析脚本 |
| `docs/flounder-hboot-analysis.md` | 设备/hboot 引导器逆向分析（移植前置资料） |
| `docs/porting-process.md` | **本次移植的完整过程与决策记录** |
| `docs/build-and-verification.md` | **第二轮：构建、产物自检、实机验证与当前引导问题** |
| `hboot-analysis/` | 设备 dump 原始产物（分区表、设备树、boot 分区备份等） |
| `out/` | 构建产物（boot.img / rootfs.img / bootimg-rescue / SHA256SUMS.txt / logs） |

## 快速开始

前置：x86_64 主机装有 Nix（ flakes 已启用）、`fastboot`（android-tools）、
串口线（强烈建议，见 `docs/flounder-hboot-analysis.md` 第 8 节）。
本环境 github.com 不可达，故 flake 直接引用本地 nixpkgs checkout
（`/home/lumiere/workspace/nixpkgs`，26.11-unstable）；依赖二进制来自
cache.nixos.org，内核源码来自 cdn.kernel.org。

```bash
# 1. 构建（交叉编译，无需 qemu；第一次会交叉编译 aarch64 userland）
NIX_MAX_JOBS=4 NIX_CORES=2 scripts/build-all.sh
#    → out/boot.img       15.2 MB 极小内核 + initramfs（loop 挂载 UDA）
#    → out/rootfs.img     NixOS rootfs (ext4，4 GiB，loop 挂载 UDA)
#    → out/bootimg-rescue 救援镜像（直接进 initramfs shell）

# 2. 结构自检（不依赖设备）
scripts/analyze-bootimg.py out/boot.img

# 3. 可选：先临时引导验证（不写入分区）
# scripts/flash-test-boot.sh         # = fastboot boot out/boot.img

# 4. 刷入 rootfs 到 UDA（userdata）分区 —— 会清空 userdata
#    默认走 TWRP + adb push 逐字节写，约 8 分钟；不要用 fastboot sparse。
scripts/flash-rootfs.sh out/rootfs.img twrp

# 5. 刷入 boot 分区（LNX）并重启
scripts/flash-boot.sh

# 6. 设备启动后接 USB OTG 键盘（tty1 root 自动登录）或 UART 串口
#    （115200 8N1，root/flounder）输入命令。
```

之后在设备上：root / `flounder` 登录（串口或 USB 键盘 + simplefb 控制台）。
目前 `/` 是 `/dev/loop0`，rootfs 固定 4 GiB（不再 growfs）。
在设备上更新内核/系统仍需要 nixpkgs 源或网络；本轮主要从主机重刷
`out/boot.img`。

## 当前硬件支持状态

> 下表的 ✅ 表示驱动/DTS 已写好且系统已能启动；🟡/❌ 表示外设
> 尚未逐个上机验证。7.2 内核已经能在真机启动（2026-10-19）。

| 部件 | 状态 | 说明 |
|---|---|---|
| 串口控制台 (ttyS0) | ✅ | UART0 @70006000，115200 |
| eMMC (26 GB) | ✅ | SDHCI4，hs200，8-bit；rootfs 所在 |
| 按键 (电源/音量±) | ✅ | gpio-keys |
| framebuffer 控制台 | ✅* | hboot 移交的 simplefb（1536×2048），`FRAMEBUFFER_CONSOLE` |
| USB host (OTG) | ✅ | xhci-tegra，可接键盘/网卡 |
| 触摸 (Synaptics RMI4, SPI) | 🟡 | DTS 已写、驱动 =m；待上机验证 |
| 充电/电量 (BQ24192/MAX17050) | 🟡 | DTS 已写、驱动 =y；待上机验证 |
| PMIC (TPS65913/Palmas) | 🟡 | 各路稳压器按下游 DT 1:1 移植；待上机验证 |
| 震动马达 | 🟡 | gpio-vibrator (模块) |
| WiFi (BCM4354) | ❌ TODO | 需要 brcmfmac 固件 + 从机器提取 NVRAM |
| 真实显示管线 (tegra-drm + JDI 面板) | ❌ TODO | `jdi,lpm089a128a` 面板驱动未进主线 |
| 音频 / 传感器 / 摄像头 | ❌ TODO | 需要写或移植驱动 |
| USB gadget (设备模式) | ❌ | 主线 xudc 只支持 Tegra210+ |
| CPU 调频 (DFLL) | ❌ TODO | 主线 tegra132 无 dfll 节点，当前定频运行 |
| 深度睡眠 (lp0) | ❌ | 建议 `no_console_suspend` 常开 |

详细原因与后续计划见 `docs/porting-process.md` 和
`docs/build-and-verification.md`。

## 常用操作

```bash
# 只重建内核+boot.img（不动 rootfs closure）
nix --extra-experimental-features 'nix-command flakes' build .#bootimg -o out/boot.img

# 查看最终内核 .config
nix build .#kernel-config -o kernel-config

# 结构检查 boot.img（cmdline/Image/DTB/ramdisk 布局）
scripts/analyze-bootimg.py out/boot.img

# 测试“内核加载到高地址”的实验镜像
scripts/test-boot-highmem.sh

# 进 flake dev shell（有 dtc / mkbootimg 可手工实验）
nix develop

# 设备上更新系统（内核需另执行 flounder-flash-boot）
nixos-rebuild switch
```
