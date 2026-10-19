# HTC Nexus 9 (flounder) — hboot 引导器分析与发行版移植资料

> 分析日期：2026-10-13
> 分析对象：一台通过 fastboot 连接的 HTC Nexus 9（代号 **flounder**，序列号 HT4ARJT01614）
> 所有产物文件保存在 `hboot-analysis/` 目录

---

## 0. "hboot" 是什么

一开始找不到资料的原因很简单：它的正式写法是 **HBOOT —— HTC 的 bootloader**。
Nexus 9 虽然属于 Google Nexus 系列，但整机由 HTC 代工，bootloader 也是 HTC 的私有实现：

- `fastboot getvar` 报告 `platform: hTCBtegra`（HTC + NVIDIA Tegra）
- 它实现了标准 fastboot 协议（USB ID `18d1:4ee0`），**支持 `fastboot boot` 临时引导**（本次分析大量利用了这一点）
- HTC 私有的 `oem` 命令（如 `oem device-info`、`oem get_identifier_token`）在这台机器上全部返回 `[ERR] Command error !!!`——比旧 HTC 手机阉割得更干净，基本就是一个"带 HTC 签的 AOSP fastboot"
- bootloader 本体（分区裸区域内的 NVCR 镜像）是**加密的**，无法直接逆向；但引导流程本身完全可以从 eMMC 布局推断（见第 4 节）

设备基本信息（`fastboot getvar all`，全文见 `hboot-analysis/getvar-all.txt`）：

| 项目 | 值 |
|---|---|
| product | **flounder**（HTC Nexus 9） |
| platform | hTCBtegra（NVIDIA Tegra K1 / Tegra132，双核 Denver，arm64） |
| version-bootloader | 3.43.0.0114 |
| version-mts | 33410787（Denver 微码 MTS 版本） |
| modelid / cidnum | 0P8210000 / **11111111**（SuperCID，工程解锁状态） |
| unlocked | **yes** |
| partition-layout | Generic |
| cpu-revision | A03 |
| IMEI | 355195000000010（测试样机 IMEI） |

---

## 1. 分析过程（可复现的操作步骤）

整个流程**没有向设备写入任何数据**，全部是只读 dump + 一次临时引导。

### 1.1 fastboot 阶段（设备在 bootloader 模式）

```bash
fastboot devices -l                 # 确认连接
fastboot getvar all > getvar-all.txt
# 探测隐藏分区是否存在（hboot 会回答已知分区的 size/type）：
fastboot getvar partition-size:dtb   # → 0x400000（DTB 分区存在，4MB）
```

注意：`getvar all` 只列出 hboot 关心的 7 个分区（hboot/recovery/boot/system/cache/userdata/vendor），**完整分区表必须从 eMMC 的 GPT 里读**（见第 5 节）。

### 1.2 临时引导 TWRP（不写入）

hboot 支持 `fastboot boot`，所以无需刷入任何东西即可获得一个带 adb 的 Linux 环境：

```bash
# 下载 flounder 的 TWRP（本机存档：hboot-analysis/twrp-flounder.img，md5=18f81ab7484d905cbae4fb3912a43290）
fastboot boot twrp-flounder.img     # 临时引导，重启即失效
adb devices                         # 等待 recovery 上线
```

> 下载来源：https://dl.twrp.me/flounder/（注意直接 GET 会被挡，需要带浏览器 UA + Referer）

### 1.3 adb 阶段（在 TWRP Linux 里只读 dump）

```bash
adb shell cat /proc/cmdline                        # hboot 传给内核的完整命令行
adb shell cat /proc/partitions                     # 内核看到的 eMMC 分区
adb shell ls -l /dev/block/platform/sdhci-tegra.3/by-name/   # 分区名 → 设备节点映射
adb shell cat /proc/iomem                          # SoC 外设寄存器映射
adb shell cat /proc/cpuinfo                        # CPU（NVIDIA Denver 1.0）

# GPT（Tegra 特殊布局：分区条目在 LBA 69599-69630，头在 LBA 69631，见第 5 节）
adb shell "dd if=/dev/block/mmcblk0 of=/tmp/gpt-mid.bin bs=512 skip=69568 count=128"
adb pull /tmp/gpt-mid.bin .

# bootloader 裸区域整体备份（LBA 0-69631，34MB）
adb shell "dd if=/dev/block/mmcblk0 of=/tmp/hboot-raw-area.bin bs=512 count=69632"
adb pull /tmp/hboot-raw-area.bin .

# 运行时设备树（就是 hboot 实际使用的 DTB 展开后的样子）
adb shell "tar -cf /tmp/devtree.tar -C /proc/device-tree ."
adb pull /tmp/devtree.tar .

# boot / recovery 分区完整备份
adb shell "dd if=/dev/block/mmcblk0p16 of=/tmp/LNX.img bs=1M count=32"
adb shell "dd if=/dev/block/mmcblk0p15 of=/tmp/SOS.img bs=1M count=32"
adb pull /tmp/LNX.img .; adb pull /tmp/SOS.img .
```

### 1.4 主机端解析

```bash
# 运行时设备树 → dts
mkdir devtree-fs && tar -xf devtree.tar -C devtree-fs
dtc -I fs -O dts -o runtime-devtree.dts devtree-fs

# boot 镜像里的内核尾部附加 DTB → dts（见 1.5 如何定位）
dtc -I dtb -O dts -o appended-kernel.dts appended-kernel.dtb

# GPT 手工解析（python，struct 解包 'EFI PART' 头 + 128 字节分区条目）
```

### 1.5 本次踩过的坑（下次直接绕开）

1. **GPT 不在磁盘开头**。LBA 0-69631 全是 bootloader 专用裸区域，标准工具 `fdisk`/`parted` 直接读整盘头部会以为没有分区表。内核命令行里的 `gpt_sector=69631` 是关键提示——GPT 头就在那个扇区，条目在它**前面**的 LBA 69599-69630。
2. **DTB 分区（mmcblk0p5）是全零的**。flounder 的设备树**不**存在独立 DTB 分区，而是**附加在 boot.img 内核镜像尾部**（Tegra Android 惯例）。在 LNX.img 里搜 FDT 魔数 `d00dfeed` 即可定位。
3. Android boot image 头解析时注意字段顺序：`kernel_size, kernel_addr, ramdisk_size, ramdisk_addr, ...`——第一遍把地址当 size 解析成了天文数字。
4. hboot 的 fastboot 不支持新版协议命令（`fetch` 等），也没有任何可用的 `oem dump` 类命令；想读任意分区只能临时引导一个 Linux（TWRP）。

---

## 2. 硬件清单（移植时的硬件支持目标）

| 部件 | 识别结果 | 依据 |
|---|---|---|
| SoC | NVIDIA Tegra K1 (Tegra132)，**双核 NVIDIA Denver 1.0**（ARMv8） | /proc/cpuinfo, DTB `compatible = "nvidia,tegra132"` |
| 内存 | 2GB（DT `memory@0x80000000`，实际可用 ~1.9GB + 多个 carveout，见第 6 节） | 设备树 |
| 存储 | eMMC ~28.9GB（`/dev/block/mmcblk0`，SDHCI 控制器 `sdhci@700b0600`，实例 sdhci-tegra.3） | /proc/partitions |
| 屏幕 | JDI QXGA 8.9" 2048×1536（DT 节点 `panel_jdi_qxga_8_9`，DSI，host1x/tegradc 驱动） | 设备树 |
| 触摸 | I2C 触摸控制器（详细节点见 runtime-devtree.dts） | 设备树 |
| WiFi/BT | Broadcom（EEPROM: `vendid=0x14e4 deviceid=0x432f boardtype=0x4b9`，xtalfreq=37400），MAC 由 hboot 注入 cmdline | 设备树 wifi_eeprom + cmdline |
| 充电 | TI BQ2419x 充电 IC + MAX17050 电量计（I2C，DT 节点 `htc_battery_bq2419x` / `htc_battery_max17050`） | 设备树 |
| USB | Tegra xUSB（xhci，`xusb@70090000`），OTG | 设备树 + iomem |
| 按键 | Power(0x74) / Vol-(0x72) / Vol+(0x73)，GPIO keys | 设备树 gpio-keys |
| TrustZone | 存在（DT 有 `trusty` 节点，TOS 分区 3MB，cmdline `tzram=4M@3962M`） | 设备树 + cmdline |
| 调试串口 | UART0 `serial@70006000`（`console=ttyS0,115200`），板侧触点 | cmdline + iomem |
| GPU | GK20A（Tegra K1 Kepler，`host1x/gk20a` @0x57000000/0x58000000） | iomem |

**CPU 细节**：enable-method = spin-table（非 PSCI 老内核），`cpu-release-addr` 0x8000fff8/0x80000008。DT 同时有 psci 节点（mainline 用）。Denver 是 NV 自研动态优化核心，**微码（MTS）由 bootloader 加载**——mainline 对 Denver 只按普通 ARMv8 对待，性能会差于下游内核。

---

## 3. hboot 引导流程（推断 + 证据）

```
eMMC LBA 布局（512B 扇区）：

LBA 0-1022      BCT 多副本（每 4KB 一块，头部 8b8d9e8f...）→ Tegra BootROM 读 SDMMC 配置
LBA 1024-2390   xloader（32 位 ARM 代码，BootROM 加载，负责加载主 bootloader）
LBA 13312+      备份/恢复镜像（ARM 代码，含 0xdeadbeef 标记）
LBA 14336       小 NVCR 容器（32KB）
LBA 38912-42013 hboot 主镜像（NVCR 容器，"NVCR" 魔数，1.5MB，HTC 加密签名）
LBA 63488       HTC-BOARD-INFO!（板级信息：CID=11111111 即 SuperCID 等）
LBA 69599-69630 GPT 分区条目（33 个分区）
LBA 69631       GPT 头（"EFI PART"，alt LBA 字段是假的，指向 61046783）
LBA 69632+      GPT 分区数据区从 KEY 分区开始
```

引导链：BootROM → (BCT) → xloader → **hboot（加密，3.43.0.0114）** → 读 LNX 分区 boot.img → 校验 → 把 kernel 加载到 0x10008000、ramdisk 到 0x11000000 → 附加 DTB 给内核 → 跳转执行。

**对移植最有用的结论**：

- bootloader 锁定已解除（`unlocked: yes`），**LNX/SOS/APP/UDA 分区随便刷**，hboot 会跳过签名校验
- `fastboot boot` 可用 → 任何实验都可以先临时引导验证，不动板上的东西
- hboot 不提供 dtb 注入（不读 DTB 分区），**设备树必须附加在内核镜像尾部**
- hboot 每次启动都会在 cmdline 里注入板级参数（serialno/wifimacaddr/内存 carveout 等），新发行版的启动配置要能容忍/利用这些（`androidboot.*` 可被 Android 解析器或 systemd-udev 处理，内存 carveout 参数需要内核侧正确保留，见第 6 节）

---

## 4. 分区表（完整 GPT，33 个分区）

机器可读版本：`hboot-analysis/partition-table.csv`
fastboot 视角的简化视图：`hboot-analysis/getvar-all.txt`

| # | GPT 名 | fastboot 名 | 设备 | 大小 | 用途/说明 |
|---|---|---|---|---|---|
| 1 | KEY | — | mmcblk0p1 | 1 MiB | 密钥（加密相关） |
| 2 | TOS | — | mmcblk0p2 | 3 MiB | **TrustZone OS** |
| 3 | EKS | — | mmcblk0p3 | 0.5 MiB | 加密密钥存储 |
| 4 | WB0 | — | mmcblk0p4 | 0.5 MiB | warmboot 数据 |
| 5 | DTB | — | mmcblk0p5 | 4 MiB | **全零，未使用**（DTB 附加在内核后） |
| 6 | RV1 | — | mmcblk0p6 | 5 MiB | 保留/恢复镜像 |
| 7 | WDM | — | mmcblk0p7 | 2 MiB | watchdog misc |
| 8 | RCA | — | mmcblk0p8 | 8 MiB | recovery 备份区 |
| 9 | SP1 | — | mmcblk0p9 | 16 MiB | misc/系统参数 |
| 10 | NCT | — | mmcblk0p10 | 2 MiB | HTC 板级配置 |
| 11 | EXT | — | mmcblk0p11 | 0.5 MiB | 扩展配置 |
| 12 | FST | — | mmcblk0p12 | 32 MiB | 文件系统表/工厂区 |
| 13 | RV2 | — | mmcblk0p13 | 12.5 MiB | 保留 |
| 14 | PG1 | — | mmcblk0p14 | 18 MiB | 保留 |
| 15 | **SOS** | recovery | mmcblk0p15 | 32 MiB | **recovery boot.img** |
| 16 | **LNX** | boot | mmcblk0p16 | 32 MiB | **主 boot.img（内核所在）** |
| 17 | MSC | misc | mmcblk0p17 | 2 MiB | misc（boot reason 等） |
| 18 | MFG | — | mmcblk0p18 | 2 MiB | 工厂模式 |
| 19 | SER | — | mmcblk0p19 | 0.5 MiB | 序列号存储 |
| 20 | DIA | — | mmcblk0p20 | 4 MiB | 诊断 |
| 21 | EF1 | — | mmcblk0p21 | 8 MiB | 保留 |
| 22 | EF2 | — | mmcblk0p22 | 8 MiB | 保留 |
| 23 | CDR | — | mmcblk0p23 | 2 MiB | 保留 |
| 24 | VNR | — | mmcblk0p24 | 256 MiB | 保留 |
| 25 | MD1 | — | mmcblk0p25 | 64 MiB | modem1 |
| 26 | MD2 | — | mmcblk0p26 | 64 MiB | modem2 |
| 27 | PST | — | mmcblk0p27 | 0.5 MiB | 保留 |
| 28 | OTA | — | mmcblk0p28 | 40 MiB | OTA 暂存 |
| 29 | **APP** | system | mmcblk0p29 | 2.6 GiB | **system（ext4），可当 rootfs 用** |
| 30 | **CAC** | cache | mmcblk0p30 | 256 MiB | cache（ext4） |
| 31 | **UDA** | userdata | mmcblk0p31 | 25.6 GiB | **userdata（f2fs），最大的分区，rootfs 首选** |
| 32 | RV3 | — | mmcblk0p32 | 15 MiB | 保留 |
| 33 | GPT | — | mmcblk0p33 | 1 MiB | GPT 自身备份 |

**移植时只需要关心**：LNX（刷内核）、SOS（可选：放救援系统）、UDA（rootfs）、APP（备用 rootfs 或数据）。

---

## 5. 启动镜像格式（mkbootimg 参数）

当前 LNX 里装的是 postmarketOS 的 boot.img（分析记录）：

```
Android boot image header v0, page_size = 2048
kernel_size  = 8098830   kernel_addr  = 0x10008000
ramdisk_size = 10580383  ramdisk_addr = 0x11000000
second_size  = 0         second_addr  = (未用)
tags_addr    = 0x10000100
cmdline      = "console=ttyS0,115200 pmos_root_uuid=69b88ee9-... pmos_rootfsopts=defaults"
DTB          = 附加在内核镜像尾部（LNX.img 偏移 0x7a6c1e，77808 字节）
```

给新发行版打 boot.img 的最小 mkbootimg 命令（内核尾部需 cat 上 dtb）：

```bash
cat Image.gz-dtb 或者 cat Image dtb.dtb > kernel-dtb    # flounder 上 DTB 必须附加在内核后
mkbootimg \
  --kernel kernel-dtb \
  --ramdisk initramfs.cpio.gz \
  --base 0x10000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --tags_offset 0x00000100 \
  --pagesize 2048 \
  --header_version 0 \
  --cmdline "console=ttyS0,115200 root=PARTUUID=..." \
  -o boot.img
fastboot flash boot boot.img     # 或先 fastboot boot boot.img 验证
```

hboot 注入的运行时 cmdline（`/proc/cmdline`，每台机器略有差异，**不要硬编码这些值**）：

```
no_console_suspend=1 tegra_wdt.enable_on_probe=1 tegra_wdt.heartbeat=120
androidboot.hardware=flounder MTS Version=33410787 memtype=0
tzram=4M@3962M ddr_die=1024M@2048M ddr_die=1024M@3072M section=128M
lp0_vec=2048@0xf7fff000 tegra_fbmem=12713984@0xac001000
nvdumper_reserved=0xf7800000 core_edp_mv=1150 core_edp_ma=4000
gpt gpt_sector=69631 watchdog=disable nck=1048576@0xf7900000
androidboot.serialno=... androidboot.wifimacaddr=... androidboot.wificountrycode=AU
androidboot.bootreason=hard_reset hw_revision=128 ...
```

## 6. 内存布局（arm64 物理地址）

```
0x80000000 - 0xF7600000   Linux 可用 RAM（DT: memory@0x80000000 size=0x77600000 ≈ 1.9GB）
0xac001000 + 12.7MB       framebuffer carveout (tegra_fbmem)
0xf7800000                nvdumper 保留区
0xf7900000 + 1MB          nck 保留区
0xf7fff000 + 2KB          lp0 向量（休眠唤醒）
0xf8000000 附近 (3962M)   tzram：TrustZone 4MB
DDR die: 1024M@2048M + 1024M@3072M（两颗 1GB）
```

> 新内核（mainline）用 DTB 的 `/reserved-memory` 声明这些保留区即可；下游 3.10 内核靠 cmdline 解析。**如果保留区声明不对，设备会随机死机**（framebuffer/tzram 被内核占用时尤其如此）。

---

## 7. 设备树产物

| 文件 | 说明 |
|---|---|
| `hboot-analysis/appended-kernel.dts` | 从当前 LNX boot.img 内核尾部提取的 DTB 反编译（**这就是 hboot 实际引导用的设备树**） |
| `hboot-analysis/appended-kernel.dtb` | 同上的二进制 |
| `hboot-analysis/runtime-devtree.dts` | 运行时 `/proc/device-tree` 导出（与上面基本一致，多了运行时注入的 chosen/bootargs） |
| `hboot-analysis/devtree-fs/` | /proc/device-tree 的原始文件树 |

根节点：`compatible = "google,flounder64", "nvidia,tegra132"; model = "Google Nexus 9"`

关键节点速查（完整内容看 dts 文件）：

- `cpus`：2× `nvidia,denver`，spin-table，release-addr 0x8000fff8 / 0x80000008；另有 `psci` 节点
- `serial@70006000`：调试串口 ttyS0（status okay）
- `sdhci@700b0600`：eMMC（注意：下游 DT 中 sdhci 节点全部标 `status="disabled"`，实际由平台代码按板配置启用——**自己写 mainline DT 时要改成 okay**，这是 Tegra 下游 DT 的经典坑）
- `xusb@70090000`：USB（xhci + OTG，同样需要显式 enable）
- `panel_jdi_qxga_8_9` + `host1x`：DSI 面板 + 显示
- `pinmux`、`gpio@6000d000`、6 个 `i2c@7000cxxx/7000dxxx`、7 个 `spi@7000dxxx`
- `emc@7001b000`（含 Denver 的 emc-table 时序表——**降频/内存稳定性调试要用**）
- `dfll@70040084` + `cpu_dfll_board_params` + `cpu_dfll_pmic_integration`：CPU 调频
- `htc_battery_bq2419x`、`htc_battery_max17050`：电源
- `regulators`：fixed regulators（en-lcd-bl、vdd-lcd、avdd-lcd、vpp-fuse、usb2-vbus、ldoen...）
- `trusty`、`htc_reboot_params`、`htc_debug_info`、`calibration_data`：HTC 私有节点
- `gpio-keys`：Power/Vol±（GPIO 节点引用 0x04，见 phandle）

> mainline 现状：`arch/arm64/boot/dts/nvidia/tegra132.dtsi` + `tegra132-norrin.dts`（开发板）已进主线；**flounder 专用 DTS 没进 mainline**，pmOS 的 aports 里有维护良好的下游版本，可作为起点改造成 mainline 风格。

---

## 8. 移植新发行版的实操路线（以 NixOS 为例）

1. **内核选择**
   - 起步：直接用 postmarketOS flounder 下游内核（3.10，硬件全可用：显示/触屏/WiFi/休眠）
   - 进阶：mainline（`nvidia/tegra132` 有基础支持：串口/eMMC/USB/显示部分可用；Denver 用 spin-table；WiFi brcmfmac 需要固件 + EEPROM 注入；触屏/摄像头/音频要自己从下游搬）
2. **rootfs**
   - 格式化 UDA（f2fs 或 ext4）：`fastboot erase userdata` 或在 TWRP 里 mkfs
   - rootfs 镜像通过 `fastboot flash userdata rootfs.img` 或 TWRP 下 adb push + dd 写入
   - NixOS 的话：`nixos-generate` 出 arm64 closure，用 qemu-aarch64 binfmt 静态注册后 chroot 安装，或者直接在别的 arm64 机器上 `nix build` 后 rsync 进 UDA
3. **boot 链**
   - 按 第 5 节 参数 mkbootimg：内核**必须尾部附加 DTB**
   - initramfs 里要能找到 root（`root=PARTUUID=` 用 UDA 的 GUID `3ae67cbd-f4d9-038d-e207-96cecb768934`，或直接 `/dev/mmcblk0p31`）
   - 先 `fastboot boot boot.img` 验证，成功再 `fastboot flash boot`
4. **串口救砖**：UART0 触点在机身（Nexus 9 拆机后有标准 4 点测试点），`console=ttyS0,115200` 永远带上；LNX 刷坏用 `fastboot boot` 或 SOS 兜底，hboot 本身在独立裸区域，刷不坏
5. **注意事项**
   - cmdline 里 `tegra_wdt.heartbeat=120`：不喂狗会重启——mainline 里确认 watchdog 驱动状态
   - `watchdog=disable` 是 hboot 传的，下游内核会尊重
   - suspend/resume（lp0_vec）在 mainline Tegra 上历来是最难啃的部分，初期建议直接 `no_console_suspend=1` + 不进深度睡眠

---

## 9. 产物文件清单（hboot-analysis/）

| 文件 | 内容 |
|---|---|
| `getvar-all.txt` | fastboot 全量变量 |
| `partition-table.csv` | 完整 GPT 分区表（机器可读） |
| `by-name-mapping.txt` | 分区名 ↔ 设备节点映射 |
| `gpt-head/mid/tail.bin` | eMMC 三个关键区域的原始扇区 |
| `hboot-raw-area.bin` | bootloader 裸区域完整备份（34MB，救砖用） |
| `htc-board-info.bin` | HTC-BOARD-INFO 区块（LBA 63488） |
| `hboot-nvcr-main.bin` | hboot 主镜像 NVCR 容器（加密，LBA 38912） |
| `xloader-arm.bin` | xloader（32 位 ARM，LBA 1024） |
| `LNX.img` / `SOS.img` | boot / recovery 分区完整备份（各 32MB） |
| `appended-kernel.dtb/.dts` | 当前实际使用的设备树 |
| `runtime-devtree.dts` + `devtree-fs/` | 运行时设备树导出 |
| `runtime-info.txt` | cpuinfo / meminfo / iomem |
| `dtb-part.bin` | DTB 分区原始内容（全零，仅作记录） |
| `twrp-flounder.img` | TWRP 3.7.0（fastboot boot 用的工具镜像） |

---

## 10. 后续可做的分析（如有需要）

- 用 `strings` 深挖 NCT 分区（HTC 板级配置：传感器校准、面板参数等）
- dump VNR/EF1/EF2 看是否有音频/摄像头固件
- 对比 pmOS 下游 DTS 与 mainline norrin DTS，整理出 flounder mainline DTS 缺口清单
- hboot NVCR 容器格式逆向（需要 HTC 泄露的密钥，实际不可行，仅记录）
