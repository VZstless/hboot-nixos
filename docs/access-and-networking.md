# 外部访问与网络支持

更新时间：2026-10-20

本文记录本轮镜像改动，以及刷入后不依赖屏幕、键盘的访问方法。改动只
作用于 boot.img、rootfs.img 和其中的内核/设备树；本轮没有向设备刷写
任何分区。

## 设备依据

- 目标设备是 HTC Nexus 9 `flounder`，序列号 `HT4ARJT01614`。
- 连接设备时主机 sysfs 枚举到 `18d1:4ee0`（`Android 1.0`），与 hboot
  fastboot 记录一致。
- 当前受限环境不能直接打开主机的 libusb/fastboot 设备节点，因此本轮
  使用仓库已有的 `hboot-analysis/runtime-devtree.dts` 和追加设备树 dump；
  没有覆盖或猜测设备树内容。
- 运行时 dump 显示旧 Tegra UTMI 控制器 `0x7d000000` 是下游 UDC，当前
  mainline Linux 7.3 已有对应的 ChipIdea Tegra glue 驱动。

## micro-USB：串口与 SSH

### 内核与设备树

镜像启用以下内核功能并全部编入最小内核：

- `USB_GADGET`、`USB_CHIPIDEA`、`USB_CHIPIDEA_UDC`、`USB_CHIPIDEA_TEGRA`；
- 旧 UTMI PHY `USB_TEGRA_PHY`；
- `USB_CDC_COMPOSITE`，它提供 CDC ACM + CDC ECM 两个接口；
- 关闭 XUSB host 的设备树节点，把 `usb@7d000000` 设置为
  `dr_mode = "peripheral"`。

这样同一根 micro-USB 线接到电脑后，设备侧应同时出现：

- `/dev/ttyGS0`：设备侧串口，主机通常枚举为 `/dev/ttyACM0`；
- `usb0`：设备侧 CDC ECM 网卡，主机通常显示为 `enx...` 或 `usb0`。

镜像还关闭 USB 自动挂起：`usbcore.autosuspend=-1`，减少串口/网卡在空闲
时掉线的概率。

### USB 串口登录

在主机上插线后查找 ACM 设备：

```sh
ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null
screen /dev/ttyACM0 115200
```

也可以使用 `picocom -b 115200 /dev/ttyACM0`。系统为 `ttyGS0` 启用了
`serial-getty`，并沿用全局 root 自动登录设置，因此不需要屏幕或键盘。
退出 `screen` 通常使用 `Ctrl-A`、`K`、`Y`。

如果内核已经启动但 ACM 没有出现，先使用主板 UART 测试点的 `ttyS0`（115200
8N1）查看早期日志；这条 UART 仍然保留，作为 USB gadget 调试的回退路径。

### USB 网络登录

设备侧固定地址是 `192.168.77.2/30`，主机侧需要给刚出现的 USB 网卡设置
`192.168.77.1/30`：

```sh
ip link
sudo ip addr add 192.168.77.1/30 dev <host-usb-interface>
sudo ip link set <host-usb-interface> up
ping 192.168.77.2
ssh root@192.168.77.2
```

初始密码仍是 `flounder`；首次登录后应立即修改。更安全的方式是把用户的
`ssh-ed25519` 公钥填入 `configuration/configuration.nix` 的
`users.users.root.openssh.authorizedKeys.keys`，然后重新构建镜像。

不需要在主机上运行 DHCP，也不需要设备端的无线凭据。NixOS 的 `usb0` 网络
配置会在 CDC ECM 接口出现后设置地址；如果主机网卡名称不同，以 `ip link`
的实际名称为准。

## BCM4354 Wi-Fi

### 驱动与设备树

镜像把 `WLAN`、`WIRELESS`、`CFG80211`、`BRCMFMAC` 和
`BRCMFMAC_SDIO` 编译进内核，并关闭不需要的 `RFKILL` 子系统，避免
Kconfig 的配置顺序把 `cfg80211` 降级为模块。板级 DTS 同时声明：

为确保 Nix 的非交互式 Kconfig 生成器在处理 `cfg80211` 之前就看到
`RFKILL=n`，内核补丁还把 arm64 `defconfig` 中的 `RFKILL=m` 和
`RFKILL_GPIO=m` 改为未设置。这是构建顺序修正，不改变设备访问方式。

- SDMMC1、4-bit、SDR104、1.8 V only；
- host-wake 中断 `TEGRA_GPIO(U, 5)`；
- `brcm,board-type = "htc,flounder"`；
- 从 hboot runtime dump 得到的 MAC `B4:CE:F6:07:07:27`。

`hardware.enableRedistributableFirmware = true` 会把 nixpkgs 的
`linux-firmware` 放入 rootfs；本仓库额外提供
`firmware/brcmfmac4354-sdio.txt`，并以以下两个名字安装：

```text
/run/current-system/firmware/brcm/brcmfmac4354-sdio.txt
/run/current-system/firmware/brcm/brcmfmac4354-sdio.htc,flounder.txt
```

由于 NixOS 会把 firmware 压缩为 zstd，最小内核同时打开了
`CONFIG_FW_LOADER_COMPRESS_ZSTD=y`，并关闭了不需要的 XZ firmware 解压器。
这保证 `brcmfmac` 可以在没有模块和 initrd helper 的情况下加载压缩固件。

后一个名字与 DTS 的 `brcm,board-type` 对应。NVRAM 文本来自
`hboot-analysis/runtime-devtree.dts` 的 `wifi_eeprom` 可读字段，没有把
其中的二进制 `RAW1` 段伪装成文本 NVRAM。

本镜像不写入任何 Wi-Fi SSID/密码，因此 `networking.wireless.enable` 保持
关闭；驱动、firmware、`iw` 和 `wpa_supplicant` 已经在镜像中。第一次通过
USB 串口或 USB SSH 登录后，可以按实际网络凭据配置无线。验收时重点查看：

```sh
dmesg | grep -E 'brcmfmac|mmc1|firmware'
iw dev
ip link show wlan0
```

如果日志报告缺少 `brcmfmac4354-sdio.bin`，说明当前 nixpkgs 的
`linux-firmware` 没有携带该 blob；这时需要把原厂 `/vendor/firmware` 中的
对应 blob 作为额外 firmware 输入，而不是修改设备树中的校准文本。

## fastfetch

`fastfetch` 已加入 `environment.systemPackages`。刷入并登录后直接运行：

```sh
fastfetch
```

## 构建与验收

本镜像对 fastfetch 做了一个局部 Nix override：移除当前 nixpkgs 在交叉
构建时错误带入的 Enlightenment EFL 构建依赖。EFL 的 `eolian_gen` 需要在
构建阶段执行目标架构程序，但本工程是在 x86_64 主机上交叉生成 aarch64
rootfs；fastfetch 的实际运行功能不依赖该可选组件。

当前本地 nixpkgs checkout 的 `linux_latest` 是 Linux 7.3；仓库的
`flake.lock` 已同步到 2026-10-20 的本地 nixpkgs 路径哈希。

```sh
nix --extra-experimental-features 'nix-command flakes' build .#kernel-config -o kernel-config
nix --extra-experimental-features 'nix-command flakes' build .#bootimg -o out/boot.img
scripts/analyze-bootimg.py out/boot.img
```

刷写前应确认内核配置至少包含上述 USB gadget/Wi-Fi 选项，并在 boot image
分析中看到 `usbcore.autosuspend=-1`。首次上机顺序建议是：

1. 用 `fastboot boot out/boot.img` 临时启动；
2. 通过 UART 或 USB ACM 查看内核日志；
3. 确认主机出现 ACM 和 ECM，再验证 `ping`/`ssh`；
4. 最后验证 `brcmfmac`、`wlan0` 和 `fastfetch`。

本轮仅完成镜像实现和静态/构建级验证，USB gadget 与 BCM4354 尚未在这次
连接上做硬件 smoke test；失败时 UART `ttyS0` 是保留的救援入口。
