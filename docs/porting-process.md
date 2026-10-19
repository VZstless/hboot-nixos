# Flounder (HTC Nexus 9) × NixOS 26.11-unstable 移植过程记录

> 日期：2026-10-19
> 目标：把 NixOS 26.11-unstable（nixpkgs master）适配到 HTC Nexus 9
> （flounder，NVIDIA Tegra132，双核 Denver，arm64，hboot 引导器）。
> 前置资料：[flounder-hboot-analysis.md](flounder-hboot-analysis.md)
>（hboot/分区表/设备树 dump 的逆向分析）。

本文档记录完整的过程、每一步的证据与决策，方便复现和继续推进。

---

## 0. TL;DR

- 用 nixpkgs 26.11 的 **linux_latest（mainline 7.2.11）** 交叉编译内核，
  打上自写的 `tegra132-flounder.dts` 设备树补丁；
- 弃用 NixOS 自带 initrd（放不进 32 MiB 的 LNX 分区），改为
  **~2 MiB 的 busybox initramfs + initrdless 直启**；
- 用 `mkbootimg` 按 hboot 约定（gzip 内核 + 尾附 DTB）组装 Android boot image；
- rootfs 用 `mkfs.ext4 -d` 打包整个 NixOS closure 刷进 UDA 分区，
  首启由 systemd-growfs 扩容到整分区；
- 产物：`out/boot.img`（刷 LNX/boot）+ `out/rootfs.img`（刷 UDA/userdata）。

## 1. 环境与约束

| 项 | 情况 | 影响 |
|---|---|---|
| nixpkgs | 本地 checkout `/home/lumiere/workspace/nixpkgs`（26.11/master, `.version`=26.11） | github.com 被墙，flake 用 `path:` 输入 |
| 网络 | cache.nixos.org、tarballs.nixos.org、cdn.kernel.org 可达；github/gitlab 不可达 | aarch64 依赖全部可从官方缓存取；内核源从 kernel.org 取；不能抓 pmOS 的下游内核 |
| 主机 | x86_64，16 核，30 GB RAM | 无 qemu-binfmt → 全程**交叉编译**（`nixpkgs.buildPlatform = "x86_64-linux"`） |
| 设备侧 | hboot 3.43.0.0114，已解锁，`fastboot boot` 可用 | 任何实验都可以先临时引导、不落盘 |
| 设备资料 | `hboot-analysis/`：完整 GPT、运行时设备树、boot/recovery 镜像备份、cmdline | 见分析文档 |

## 2. 内核选型

**决策：nixpkgs `linux_latest` = mainline 7.2.11（stable 主线）**，
不用 `linux_testing`(7.3-rc7)、不用下游 3.10。

理由：
1. 用户要求"最新的主线内核，用 nixos 中的"→ `linux_latest` 是 nixpkgs
   26.11 中最新的主线稳定版（`kernels-org.json`: 7.2.11；`linux_testing`
   是 7.3-rc7，且源在 git.kernel.org 的 tarball，本环境可达性不稳）。
2. Tegra132 自 4.x 起就在主线：`tegra132.dtsi`、Denver CPU、sdhci-tegra、
   xhci-tegra、Palmas PMIC、brcmfmac、RMI4 触摸等驱动全部在树内。
   7.2 相比 6.12 的 tegra132.dtsi 几乎无差异（仅 dma 节点改名、加了
   firmware 节点），内核 arm64 defconfig 已含 `ARCH_TEGRA`、
   `SERIAL_TEGRA`、`MMC_SDHCI_TEGRA`、`USB_XHCI_TEGRA`、
   `PHY_TEGRA_XUSB`、`EXTCON_USB_GPIO` 等。
3. 下游 3.10 无法满足 NixOS 26.11（glibc 2.44 最低内核要求 3.2 虽然够，
   但 systemd 258、rust 工具链等实际要求 ≥ 5.x 内核特性），且 github
   不可达拿不到 pmOS 源。

**交叉验证过的事实**（对着 7.2.11 源码逐条确认）：
- `ARCH_TEGRA_132_SOC` 定义在 `drivers/soc/tegra/Kconfig`，默认随
  `ARCH_TEGRA` 打开，`tegra132-*.dtb` 会正常构建；
- `soctherm` 驱动有 `"nvidia,tegra132-soctherm"` 显式支持；
- `sdhci-tegra` 支持 `"nvidia,tegra124-sdhci"`（eMMC 用）；
- **xudc（USB 设备模式）只支持 Tegra210+**，flounder 的 fastboot 式
  gadget 模式在主线不可用 —— OTG host 可用（xhci-tegra）；
- `syna,rmi4-spi`（触摸）主线 binding 存在，注意函数子节点要写成
  `rmi4-f01@1 { syna,nosleep-mode = <1>; }`（下游 3.10 的
  `syna,nosleep` 属性名已改）。

## 3. 设备树：`tegra132-flounder.dts` 从零重写

主线只有 `tegra132-norrin.dts`（NVIDIA 开发板）。flounder 的 DTS 按
以下方法重写（`kernel/dts/tegra132-flounder.dts`）：

**数据来源** = `hboot-analysis/appended-kernel.dts`（hboot 实际使用的
下游 3.10 DT 的反编译）。所有硬件参数（GPIO 编号、稳压器电压、pinmux
上下拉、I2C 地址、时钟引用）都从它逐条翻译，不从记忆或猜测定值。

翻译规则与要点：
- **GPIO phandle 数字 → TEGRA_GPIO(port, pin) 宏**：
  `n = port*8 + pin`（A=0 … Z=25, AA=26 … FF=31）。
  例：电源键 `<0x0a 0x80 0x01>` → 128 = Q0 → `TEGRA_GPIO(Q, 0)`；
  WiFi enable 191 = X7；触摸中断 82 = K2；充电中断 72 = J0；
  振动马达 163 = U3；OTG ID 178 = W2；面板 DCDC 使能 245 = EE5。
- **pinmux**：下游 `pinmux@70000868` 的整段配置（约 60 组引脚）原样
  翻译成主线 `pinctrl-tegra124` 语法（`TEGRA_PIN_PULL_*` 等宏）。
  调试串口 = pu0/pu1 复用为 `uarta`；eMMC = sdmmc4_* 组；WiFi = sdmmc1_* 组。
- **内存**：`memory@80000000` 只声明 0x77600000（0x80000000–0xf7600000），
  其余 2 GiB 里的保留区（nvdumper@0xf7800000、nck@0xf7900000、tzram
  4M@3962M、lp0@0xf7fff000）本来就在 memory 节点之外，不必再声明；
  在 RAM 内部的区域用 `reserved-memory` + `no-map` 保留：
  - framebuffer `0xac001000/0xc20000`（hboot 移交的活帧缓冲）；
  - `0xf5c00000/0x200000`（hboot persistent_ram/ramoops 区）；
  - 两个 spin-table 邮箱页（`0x80000000`、`0x8000f000`）。
  **保留区声明错误会导致随机死机**（下游靠 cmdline 参数解析，主线必须
  显式声明）。
- **CPU**：主线 tegra132.dtsi 的 cpu 节点没有 enable-method，板级补上
  `spin-table` + `cpu-release-addr`（cpu0=0x8000fff8，cpu1=0x80000008，
  与运行时 DT 一致；hboot 会先把副核停在这些邮箱上再跳内核）。
  下游 DT 里还有个 PSCI 0.1 节点，但 hboot 是否实现未验证，spin-table
  是 3.10 下游实际在用的路径，风险最小。
- **simple-framebuffer**：hboot 每次启动都会点亮屏幕并把帧缓冲设在
  0xac001000（cmdline `tegra_fbmem=12713984@0xac001000`），DSI 双通道
  ganged 模式。DTS 在 chosen 下声明 simplefb（1536×2048×32、stride 6144、
  `a8b8g8r8`，时钟 DISP1/DSIA/DSIB），内核 `FB_SIMPLE=y` 即可获得
  帧缓冲控制台。主线 simplefb 的格式表确认支持 `a8b8g8r8`。
  **注意**：tegra-drm 一旦接管且没有面板驱动，会把 simplefb 弄丢，所以
  本版把 DSI/panel 相关节点全部保持 disabled。
- **PMIC（TPS65913/Palmas）**：主线 MFD 驱动完整支持。regulator 树按
  下游 1:1 翻译（smps123 vdd-cpu 650–1400mV always-on、smps8 vdd-1v8、
  ldo1 avdd-pll 1.05V、ldo5 avdd-dsi-csi 等），只是去掉了主线不认识的
  `ti,roof-floor` 优化属性。PMIC 中断走 GIC 86（pwr_int_n 引脚复用
  "pmi"，直连 GIC，与 norrin 的 as3722 相同路径）。
- **电池**：bq24192@6b（主线 `ti,bq24190` 驱动兼容 bq24192）+
  max17050@36（主线 `BATTERY_MAX17042`），加 `/battery` simple-battery
  节点（6700 mAh 设计容量）供 monitored-battery 引用。
- **USB**：只启用 padctl usb2-0 lane，function 从下游的 `snps` 改为
  `xusb`（主线 xhci 用），port 模式 `otg`；padctl 四路供电
  （avdd-pll-utmip←vdd-1v8 等）按下游映射到 Palmas 稳压器。
  extcon-usb-gpio（ID 引脚 W2）已声明。
- **明确不做/保持 disabled 的**：DSI 面板（jdi,lpm089a128a 无主线驱动）、
  audio（rt5677/tfa9895 编解码链路复杂）、NCT1008 温度传感器（无主线
  驱动）、HTC sensorhub、pcie/sata/hdmi（平板没用到）。

**验证方法**：从 cdn.kernel.org 下载 linux-7.2.11 源码（缓存于
`.src-cache/`），用 `cpp + dtc` 离线编译该 DTS 通过（仅剩上游 dtsi
自身的警告），再打成
`kernel/0001-arm64-dts-nvidia-Add-support-for-the-HTC-Nexus-9-flounder.patch`。

## 4. 启动链设计（关键约束：LNX 分区只有 32 MiB）

**事实**：
- hboot 只会从 LNX（32 MiB）读 Android boot image v0；
- 当前 LNX 里的 pmOS 镜像证明 hboot 能解压 **gzip 内核**，且 DTB 是
  追加在压缩流末尾（`Image.gz` ++ `dtb`），DTB 分区本身是全零不用的；
- mkbootimg 参数（从现存镜像反推，见分析文档第 5 节）：
  `--base 0x10000000 --kernel_offset 0x00008000 --ramdisk_offset
  0x01000000 --tags_offset 0x00000100 --pagesize 2048 --header_version 0`。

**尺寸计算**：
- mainline 7.2 arm64 `Image` ≈ 38 MiB，gzip 后 ≈ 9–11 MiB；
- NixOS 默认 stage-1 initrd（udev/systemd 工具链 + 模块）zstd 后
  通常 30–60 MiB → **放不下**。

**方案**：
1. 把引导路径全部内建进内核（`EXT4_FS=y`、`MMC_SDHCI_TEGRA=y`、
   `SERIAL_TEGRA=y`、`USB_XHCI_TEGRA=y`、`FB_SIMPLE=y`…）；
2. `boot.initrd.enable = false`，NixOS 完全走 initrdless；
3. boot.img 里塞一个自制的 **busybox 静态 initramfs（~2 MiB）**：
   等 `/dev/mmcblk0p31` → 挂载 → `switch_root` 到
   `/nix/var/nix/profiles/system/init`；失败则落到串口 rescue shell
   （对首次点亮排障极其有用）。救援镜像 `bootimg-rescue` 通过
   `init=/bin/sh` 直接进 initramfs shell。
4. `nix/flounder-bootimg.nix` 组装 boot.img，并在构建时断言总大小
   < 32 MiB。

boot.img cmdline：`console=ttyS0,115200n8 no_console_suspend
earlycon=uart8250,mmio32,0x70006000 root=/dev/mmcblk0p31 rw`。
hboot 注入的参数（androidboot.*、内存 carveout、gpt_sector 等）
由内核忽略或由 udev/systemd 处理，互不冲突。

## 5. rootfs：ext4 镜像 + 首启扩容

- UDA（userdata，26.2 GiB）当根分区；APP(system) 备用。
- `nix/flounder-rootfs.nix`：`closureInfo` 拿到 toplevel 的完整闭包，
  `cp` 进临时根，再 `mkfs.ext4 -F -d rootfs -E lazy_itable_init=0,...`
  生成镜像；`/nix/var/nix/profiles/system` 等 symlink 照常指向 store。
- 镜像故意只做 4 GiB：刷写快（sparse/分块传输），首启
  `fileSystems."/" = { options = [ "x-systemd.growfs" ]; }` 由
  systemd-growfs 扩到整个分区。
- root= 用设备名 `/dev/mmcblk0p31`（这台机器 mmc 序号固定：
  aliases mmc0=700b0600）而不是 PARTUUID，避免 hboot 的 GPT
  unique GUID 与内核重读值不一致的边角问题（分析文档第 5 节
  提到 GPT 头的 alt LBA 是假的，内核 `gpt_sector=69631` 修正后
  PARTUUID 应该也能用，后续可切换）。

## 6. 交叉编译 NixOS（x86_64 → aarch64）

flake 里同时设置：
```nix
nixpkgs.hostPlatform   = "aarch64-linux";
nixpkgs.buildPlatform  = "x86_64-linux";
```
**坑**：只设 hostPlatform 时，nixpkgs 把 buildPlatform 也当成 aarch64
（native aarch64 构建），内核 config 派生会报
`Cannot build ... Reason: platform mismatch`。必须显式两行都写。

aarch64 closure 的二进制依赖（glibc、systemd、busybox-static、
aarch64 gcc 工具链等）几乎全部命中 cache.nixos.org（约 1.4 GiB 下载）；
本地只编译：内核（含我们的补丁）、config、initramfs、boot.img、
rootfs 镜像和少量本地包。

## 7. 过程中踩过的坑（按时间顺序）

1. **`nix flake` 报 "not tracked by Git"** —— 工程目录要先 `git init`
   并把文件加入索引（`.src-cache/` 内嵌了内核源码树，里面又有 .git，
   必须 gitignore/exclude 掉）。
2. **structuredExtraConfig 传函数报 TypeError** —— 26.11 里它必须是
   attrset，在调用点 `(import ../kernel/kernel-config.nix) { inherit lib; }`。
3. **与 common-config.nix 的值冲突**（如 `USB_XHCI_TEGRA` 主线默认
   `m`）—— 我们的配置片段全部用 `lib.mkForce` 包裹。
4. **`services.journald.extraConfig` 已被移除** —— 26.11 用
   `services.journald.settings.Journal`。
5. **`linux_latest.override` 会丢掉原 kernelPatches**（实际不会丢，
   override 保留默认参数；但**重复**添加 bridge_stp_helper 会把补丁
   打两遍而失败）—— 见 flounder-hardware.nix 里的注释。
6. **两个 nix build 共用一个日志文件 + 误杀进程** —— 教训：每次
   构建用独立日志。

## 8. 尚未完成 / 已知风险（TODO 清单）

按优先级排序，前两项是上机验证的必做项：

1. **上机验证**（本仓库所有产物都已就绪，等串口/设备时间）：
   1. `scripts/flash-test-boot.sh` 先验证内核 + DTS + initramfs；
      串口应出现 `earlycon` → `Kernel command line` → eMMC 探测 →
      （rootfs 未刷时）rescue shell。
   2. 刷 rootfs 后完整启动到 NixOS login。
2. **PMIC 风险点**：Palmas 中断类型（下游 flag 为 0/none，我按 norrin
   惯例写了 LEVEL_HIGH）如果错了会表现为 I2C 中断风暴/挂起 ——
   串口日志里盯 `palmas`；必要时改成 EDGE_FALLING 试验。
   另外主线上电时如果 Palmas regulator 初始化把 vdd-cpu 设到错误
   电压会直接死机 —— 真出问题就把 PMIC 相关节点先全部 disable，
   只留 always-on 稳压器（hboot 已经把它们打开了）。
3. **CPU 二核**：spin-table 如果 hboot 实现与预期不符，表现为只有
   单核上线（不致命）；上机后 `cat /proc/cpuinfo` 确认。
4. **WiFi**：需要 ① linux-firmware 的 `brcmfmac4354-sdio.bin`
   （gitlab 不可达，需找替代源或从设备 TWRP 下 dump 出
   /vendor/firmware）② NVRAM：从设备 DT 里的 wifi_eeprom/或
   cmdline 注入的 wifimacaddr 构造 `brcmfmac4354-sdio.txt`。
5. **显示管线**：写一个 `panel-jdi-lpm089a128a` 主线驱动
   （参考 drivers/gpu/drm/panel/panel-jdi-lpm102a188a.c 和下游
   DTS 的时序），接 tegra-dsi ganged mode + pwm 背光（ph1/pwm1，
   使能引脚 avdd-lcd R0 / iovdd-lcd Q2 / dcdc-en EE5）。完成后可
   上 wayland。
6. **CPU 调频**：把 tegra124 的 DFLL 节点（70040084，下游 DT 有完整
   的 emc/dfll 参数）移植到 tegra132 板级 DTS + `tegra124-cpufreq`。
   当前 CPU 固定在 hboot 设定的频率。
7. **音频**（AHUB/i2s + rt5677）、**传感器**（htc sensorhub 私有协议，
   难）、**摄像头**、**lp0 深度睡眠**。
8. **上游化**：DTS 整理成可提交的 patch series（binding 检查
   `make dt_binding_check`、拆 regulator/pinctrl 等）投到
   linux-tegra 邮件列表；NixOS 侧可考虑做成 flake 的
   nixos-hardware 风格模块。

## 9. 复现清单（从零到刷机）

```bash
git -C /home/lumiere/workspace/nixpkgs checkout master   # 26.11-unstable
cd /home/lumiere/workspace/hboot-nixos
scripts/build-all.sh
#    out/boot.img, out/bootimg-rescue, out/rootfs.img
fastboot devices                    # 设备在 bootloader 模式
scripts/flash-test-boot.sh          # 临时引导（看串口）
scripts/flash-rootfs.sh             # UDA 写入 rootfs
scripts/flash-test-boot.sh          # 再临时引导一次，进 NixOS
scripts/flash-boot.sh               # 正式刷 LNX
```

串口：拆机后主板上有 4 个测试点（UART0 TX/RX/GND），115200 8N1。
LNX 刷坏不慌：hboot 在独立裸区域（LBA 38912，38.9 MiB 处），刷
boot 分区永远砖不了 bootloader，`fastboot boot twrp-flounder.img`
随时可救。

## 10. 产物索引

| 文件 | 说明 |
|---|---|
| `out/boot.img` | Android boot image（7.2.11 内核.gz + flounder DTB + busybox initramfs） |
| `out/bootimg-rescue` | 救援版（init=/bin/sh 直接进 initramfs） |
| `out/rootfs.img` | NixOS 26.11 aarch64 rootfs（ext4，4 GiB，首启自动扩容） |
| `kernel/dts/tegra132-flounder.dts` | 主线风格设备树（核心新代码） |
| `kernel/0001-*.patch` | 打进 nixpkgs linux_latest 的内核补丁 |
| `kernel/kernel-config.nix` | 内核配置片段 |
| `nix/*.nix` | initramfs / bootimg / rootfs 构建逻辑 |
| `configuration/*.nix` | NixOS 配置与硬件模块 |
| `scripts/*.sh` | 构建 + 刷机流程 |
