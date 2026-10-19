# Minimal kernel config for the HTC Nexus 9 (flounder).
#
# Used with `enableCommonConfig = false`, i.e. on top of the arm64
# defconfig only (no nixpkgs common-config).  The goal is a kernel
# whose decompressed Image is well below hboot's limit: hboot refuses
# to boot a kernel whose gzip output is larger than ~40-48 MiB
# (measured on the device: 40 MiB boots, 48 MiB does not).  The full
# nixpkgs config produced 69 MiB and was rejected before the jump.
#
# Everything needed by NixOS/systemd is built in; there are no
# loadable modules.

{ lib }:

with lib.kernel;
with lib;

let
  force = mkForce;
in

{
  # --- Basic platform ------------------------------------------------------
  EXPERT = force no;
  MODULES = force yes;
  NR_CPUS = force (freeform "4");
  COMPAT = force no;
  RUST = force no;

  # Non-EFI device: EFI_ZBOOT turns Image into an EFI PE/zboot file.
  EFI = force no;
  EFI_STUB = force no;
  EFI_ZBOOT = force no;

  # Size/debug trimming.
  DEBUG_INFO = force no;
  DEBUG_INFO_BTF = force no;
  DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT = force no;
  KALLSYMS_ALL = force no;
  PRINTK_INDEX = force no;
  FTRACE = force no;
  KPROBES = force no;
  BPF_SYSCALL = force no;
  BPF_JIT = force no;
  PERF_EVENTS = force no;
  DEBUG_KERNEL = force no;
  IKCONFIG = force no;

  # --- SoC / platform ------------------------------------------------------
  ARCH_TEGRA = force yes;
  ARCH_TEGRA_132_SOC = force yes;
  # Only Tegra132: the other Tegra SoC options pull in BPMP/IVC
  # (Tegra186+) drivers, which hang on a Tegra132 because there is no
  # BPMP processor.
  ARCH_TEGRA_2x_SOC = force no;
  ARCH_TEGRA_3x_SOC = force no;
  ARCH_TEGRA_114_SOC = force no;
  ARCH_TEGRA_124_SOC = force no;
  ARCH_TEGRA_210_SOC = force no;
  ARCH_TEGRA_186_SOC = force no;
  ARCH_TEGRA_194_SOC = force no;
  ARCH_TEGRA_234_SOC = force no;
  ARCH_TEGRA_238_SOC = force no;
  ARCH_TEGRA_241_SOC = force no;
  ARCH_TEGRA_264_SOC = force no;
  TEGRA_BPMP = force no;
  TEGRA_IVC = force no;
  TEGRA_HSP_MBOX = force no;
  TEGRA_ACONNECT = force no;
  TEGRA_AHB = force no;
  SOC_TEGRA_POWERGATE_BPMP = force no;
  CLK_TEGRA_BPMP = force no;
  I2C_TEGRA_BPMP = force no;
  RESET_TEGRA_BPMP = force no;
  TEGRA_BPMP_THERMAL = force no;
  PINCTRL_TEGRA = force yes;
  PINCTRL_TEGRA124 = force yes;
  # Keep the image below the ramdisk at 0x11000000; thermal/touch/
  # battery drivers can be re-enabled once the basic boot works.
  TEGRA_SOCTHERM = force no;
  TEGRA20_APB_DMA = force yes;
  THERMAL = force no;
  PWM = force no;

  # --- No ACPI / PCI / virt ------------------------------------------------
  ACPI = force no;
  PCI = force no;
  # The Tegra132 SMMU is not needed for basic bring-up and a
  # misconfigured stream ID can hang DMA; disable it first.
  IOMMU_SUPPORT = force no;
  ARM_SMMU = force no;
  ARM_SMMU_V3 = force no;
  TEGRA_IOMMU_SMMU = force no;
  XEN = force no;
  HYPERV = force no;
  KVM = force no;
  VIRTUALIZATION = force no;
  VHOST = force no;

  # --- Boot path -----------------------------------------------------------
  BLK_DEV_INITRD = force yes;
  RD_GZIP = force yes;
  DEVTMPFS = force yes;
  DEVTMPFS_MOUNT = force yes;
  TMPFS = force yes;

  SERIAL_8250 = force yes;
  SERIAL_8250_CONSOLE = force yes;
  SERIAL_TEGRA = force yes;
  SERIAL_EARLYCON = force yes;

  EXT4_FS = force yes;
  EXT4_FS_POSIX_ACL = force yes;
  CRYPTO = force yes;
  CRYPTO_CRC32C = force yes;

  MMC = force yes;
  RPMB = force yes;
  MMC_BLOCK = force yes;
  MMC_BLOCK_MINORS = force (freeform "64");
  MMC_SDHCI = force yes;
  MMC_SDHCI_PLTFM = force yes;
  MMC_SDHCI_TEGRA = force yes;

  # --- systemd / NixOS basics ---------------------------------------------
  CGROUPS = force yes;
  NAMESPACES = force yes;
  USER_NS = force yes;
  PID_NS = force yes;
  NET_NS = force yes;
  UTS_NS = force yes;
  IPC_NS = force yes;
  SECCOMP = force yes;
  SECCOMP_FILTER = force yes;
  # Drop audit/IPv6 only to make the decompressed Image fit below the
  # ramdisk at 0x11000000; both can be re-enabled later.
  AUDIT = force no;
  EPOLL = force yes;
  INOTIFY_USER = force yes;
  FANOTIFY = force yes;
  SIGNALFD = force yes;
  TIMERFD = force yes;
  EVENTFD = force yes;
  FUTEX = force yes;
  BINFMT_ELF = force yes;
  BINFMT_SCRIPT = force yes;
  TMPFS_POSIX_ACL = force yes;
  TMPFS_XATTR = force yes;

  NET = force yes;
  UNIX = force yes;
  INET = force yes;
  IPV6 = force no;
  PACKET = force yes;

  # --- Display: legacy simplefb (much smaller than DRM/simpledrm) ----------
  # The simple-framebuffer node under /chosen is turned into a platform
  # device by drivers/of/platform.c, so FB_SIMPLE binds it directly.
  DRM = force no;
  DRM_SIMPLEDRM = force no;
  DRM_FBDEV_EMULATION = force no;
  DRM_TEGRA = force no;
  SYSFB = force no;
  FB = force yes;
  FB_SIMPLE = force yes;
  VT = force yes;
  FRAMEBUFFER_CONSOLE = force yes;
  LOGO = force no;

  # --- USB host (keyboard/storage) ----------------------------------------
  USB_SUPPORT = force yes;
  USB = force yes;
  USB_XHCI_HCD = force yes;
  USB_XHCI_TEGRA = force yes;
  PHY_TEGRA_XUSB = force yes;
  USB_HID = force yes;
  HID = force yes;
  HID_GENERIC = force yes;
  # No SCSI/USB storage for now; it saves ~2 MiB and is not needed to
  # reach the root filesystem (eMMC only).
  USB_STORAGE = force no;
  SCSI = force no;
  BLK_DEV_SD = force no;
  VFAT_FS = force no;
  NLS_CODEPAGE_437 = force no;
  NLS_ISO8859_1 = force no;

  # --- I2C / SPI / PMIC / battery / touch / keys --------------------------
  I2C = force yes;
  I2C_TEGRA = force yes;
  SPI = force no;
  SPI_TEGRA114 = force no;
  GPIO = force yes;
  GPIOLIB = force yes;
  GPIO_TEGRA = force yes;

  MFD_PALMAS = force yes;
  REGULATOR = force yes;
  REGULATOR_PALMAS = force yes;
  REGULATOR_FIXED_VOLTAGE = force yes;
  POWER_SUPPLY = force no;
  BATTERY_MAX17042 = force no;
  CHARGER_BQ24190 = force no;
  EXTCON = force yes;
  EXTCON_USB_GPIO = force yes;

  INPUT = force yes;
  INPUT_EVDEV = force yes;
  KEYBOARD_GPIO = force yes;
  INPUT_GPIO_VIBRA = force no;
  RMI4_CORE = force no;
  RMI4_SPI = force no;

  # --- Disable everything that cannot work / is not needed ----------------
  SND = force no;
  SOUND = force no;
  MEDIA_SUPPORT = force no;
  WLAN = force no;
  WIRELESS = force no;
  CFG80211 = force no;
  MAC80211 = force no;
  BT = force no;
  NETFILTER = force no;
  NET_SCHED = force no;
  BRIDGE = force no;
  VLAN_8021Q = force no;
  BONDING = force no;
  TEAM = force no;
  MACVLAN = force no;
  IPVLAN = force no;
  VXLAN = force no;
  GENEVE = force no;
  VETH = force no;
  TUN = force no;
  DUMMY = force no;
  IFB = force no;
  ETHERNET = force no;
  INFINIBAND = force no;
  ISDN = force no;
  HAMRADIO = force no;
  STAGING = force no;
  IIO = force no;
  HWMON = force no;
  ATA = force no;
  MD = force no;
  BLK_DEV_DM = force no;
  BCACHE = force no;
  NVME = force no;
  XFS_FS = force no;
  BTRFS_FS = force no;
  F2FS_FS = force no;
  JFS_FS = force no;
  GFS2_FS = force no;
  OCFS2_FS = force no;
  REISERFS_FS = force no;
  NILFS2_FS = force no;
  NTFS_FS = force no;
  NTFS3_FS = force no;
  UDF_FS = force no;
  ISO9660_FS = force no;
  SQUASHFS = force no;
  EROFS_FS = force no;
  UBIFS_FS = force no;
  JFFS2_FS = force no;
  CRAMFS = force no;
  MINIX_FS = force no;
  ROMFS_FS = force no;
  NFS_FS = force no;
  NFSD = force no;
  CIFS = force no;
  CEPH_FS = force no;
  FUSE_FS = force no;
  SECURITY = force no;
  IMA = force no;
  INTEGRITY = force no;
  KEXEC = force no;
  CRASH_DUMP = force no;
  HIBERNATION = force no;
  SUSPEND = force no;
  CPU_FREQ = force no;
  CPU_IDLE = force no;
  USB_GADGET = force no;
  USB_DWC2 = force no;
  USB_DWC3 = force no;
  USB_CHIPIDEA = force no;
  USB_MUSB_HCD = force no;
  USB_MUSB_DUAL_ROLE = force no;
  USB_EHCI_HCD = force no;
  USB_OHCI_HCD = force no;
  USB_UHCI_HCD = force no;
  USB_SERIAL = force no;
  USB_NET_DRIVERS = force no;
  SCSI_LOWLEVEL = force no;
  SCSI_SAS = force no;
  SCSI_ISCSI_ATTRS = force no;
  SCSI_FC_ATTRS = force no;
  SCSI_DEBUG = force no;
  MEGARAID_NEWGEN = force no;
  MMC_SDHCI_PCI = force no;
  MMC_SDHCI_ACPI = force no;
  MMC_SDHCI_OF_ARASAN = force no;
  MMC_SDHCI_OF_ESDHC = force no;
  MMC_SDHCI_OF_DWCMSHC = force no;
  MMC_SDHCI_OF_SPARX5 = force no;
  MMC_SDHCI_XENON = force no;
  MMC_SDHCI_MSM = force no;
  MMC_SDHCI_IPROC = force no;
  MMC_SDHCI_BRCMSTB = force no;
  MMC_SDHCI_CADENCE = force no;
  MMC_SDHCI_ESDHC_IMX = force no;
  MMC_SDHCI_F_SDH30 = force no;
  MMC_SDHCI_HSIC_MMC = force no;
  MMC_SDHCI_LOONGSON2 = force no;
  MMC_SDHCI_MTK = force no;
  MMC_SDHCI_PXAV2 = force no;
  MMC_SDHCI_PXAV3 = force no;
  MMC_SDHCI_SPEAR = force no;
  MMC_SDHCI_ST = force no;
  MMC_SDHCI_S3C = force no;
  MMC_SDHCI_UHS2 = force no;
  MMC_SDHCI_AM654 = force no;
  MMC_SDHCI_BCM_KONA = force no;
  MMC_SDHCI_CNS3XXX = force no;
  MMC_SDHCI_DOVE = force no;
  MMC_SDHCI_TANGO = force no;

  # Only Tegra132: drop all other arm64 platform support.
  ARCH_ACTIONS = force no;
  ARCH_AIROHA = force no;
  ARCH_SUNXI = force no;
  ARCH_ALPINE = force no;
  ARCH_APPLE = force no;
  ARCH_ARTPEC = force no;
  ARCH_ASPEED = force no;
  ARCH_AXIADO = force no;
  ARCH_BCM = force no;
  ARCH_BCM2835 = force no;
  ARCH_BCM_IPROC = force no;
  ARCH_BCMBCA = force no;
  ARCH_BRCMSTB = force no;
  ARCH_BERLIN = force no;
  ARCH_BLAIZE = force no;
  ARCH_BST = force no;
  ARCH_CIX = force no;
  ARCH_EXYNOS = force no;
  ARCH_K3 = force no;
  ARCH_LG1K = force no;
  ARCH_HISI = force no;
  ARCH_KEEMBAY = force no;
  ARCH_MEDIATEK = force no;
  ARCH_MESON = force no;
  ARCH_MICROCHIP = force no;
  ARCH_SPARX5 = force no;
  ARCH_MVEBU = force no;
  ARCH_NXP = force no;
  ARCH_LAYERSCAPE = force no;
  ARCH_MXC = force no;
  ARCH_S32 = force no;
  ARCH_MA35 = force no;
  ARCH_NPCM = force no;
  ARCH_QCOM = force no;
  ARCH_REALTEK = force no;
  ARCH_RENESAS = force no;
  ARCH_ROCKCHIP = force no;
  ARCH_SEATTLE = force no;
  ARCH_INTEL_SOCFPGA = force no;
  ARCH_SOPHGO = force no;
  ARCH_STM32 = force no;
  ARCH_SYNQUACER = force no;
  ARCH_TESLA_FSD = force no;
  ARCH_SPRD = force no;
  ARCH_THUNDER = force no;
  ARCH_THUNDER2 = force no;
  ARCH_UNIPHIER = force no;
  ARCH_VEXPRESS = force no;
  ARCH_VISCONTI = force no;
  ARCH_XGENE = force no;
  ARCH_ZYNQMP = force no;
}
