# Kernel configuration fragment for the HTC Nexus 9 (flounder).
#
# Applied as `structuredExtraConfig` on top of nixpkgs' linux_latest
# (mainline, currently 7.2.x) and the arm64 defconfig via
# pkgs/os-specific/linux/kernel/common-config.nix.
#
# Everything needed to reach, mount and use the root filesystem is
# built into the kernel image (no modules in the boot path), because
# the boot image (LNX partition) is only 32 MiB and hboot does not
# support anything else than kernel+dtb+initrd.

{ lib }:

with lib.kernel;
with lib;

let
  # Our values must win over common-config.nix defaults.
  force = mkForce;
in

{
  # --- SoC / platform -----------------------------------------------------
  ARCH_TEGRA = force yes;
  ARCH_TEGRA_132_SOC = force yes;
  PINCTRL_TEGRA124 = force yes;
  TEGRA_SOCTHERM = force yes;
  TEGRA20_APB_DMA = yes;

  # No Rust drivers on this board; saves a ~700 MiB rust toolchain
  # download/build (nixpkgs force-enables RUST on aarch64 >= 6.12).
  RUST = force no;

  # --- Boot image format ---------------------------------------------------
  # nixpkgs enables CONFIG_EFI_ZBOOT for aarch64 (common-config.nix).  That
  # turns arch/arm64/boot/Image into a self-decompressing PE/EFI zboot
  # image, whose entry point is an EFI stub -- hboot is *not* EFI and
  # simply jumps to the start of the decompressed Image, so it ends up
  # executing the wrong code (verified: `fastboot boot` returns to
  # fastboot, while the old pmOS Image boots).  Disable the whole EFI
  # path; with CONFIG_EFI=n the image starts with a plain NOP + branch,
  # exactly like the downstream/pmOS Image.
  EFI = force no;
  EFI_STUB = force no;
  EFI_ZBOOT = force no;

  # --- Trim subsystems that cannot work on this tablet ---------------------
  # This is not required for correctness, but the default nixpkgs config
  # builds every DRM/WiFi/audio/media driver as a module, which makes a
  # full kernel build take ~1 hour.  None of these can be used on
  # flounder yet (no panel driver, no BCM4354 firmware, no audio, no
  # cameras), and disabling them also keeps the kernel image small.
  DRM_TEGRA = force no;      # would fight simpledrm for the display
  DRM_AMDGPU = force no;
  DRM_RADEON = force no;
  DRM_NOUVEAU = force no;
  DRM_XE = force no;
  DRM_MSM = force no;
  DRM_VIRTIO_GPU = force no;
  DRM_BOCHS = force no;
  DRM_QXL = force no;
  DRM_VMWGFX = force no;
  DRM_CIRRUS_QEMU = force no;
  DRM_VKMS = force no;
  SND = force no;
  SOUND = force no;
  MEDIA_SUPPORT = force no;
  WLAN = force no;
  BT = force no;
  INFINIBAND = force no;
  ISDN = force no;
  HAMRADIO = force no;
  STAGING = force no;
  IIO = force no;

  # --- Boot path: serial console, eMMC, ext4 (all built-in) ---------------
  SERIAL_8250 = force yes;
  SERIAL_8250_TEGRA = force yes; # deprecated alias, harmless
  SERIAL_TEGRA = force yes;
  MMC = force yes;
  # mmcblk0p31 (UDA) must exist in the initramfs, before any module
  # can be loaded -> MMC_BLOCK has to be built in (default is =m).
  # MMC_BLOCK depends on (RPMB || !RPMB); with RPMB=m Kconfig caps
  # MMC_BLOCK at m, so RPMB has to be built in as well.
  RPMB = force yes;
  MMC_BLOCK = force yes;
  # The GPT has 33 partitions; the default of 32 minors makes the
  # last ones unreachable.  p31 is our root, so be generous.
  MMC_BLOCK_MINORS = force (freeform "64");
  MMC_SDHCI = force yes;
  MMC_SDHCI_TEGRA = force yes;
  EXT4_FS = force yes;
  EXT4_FS_POSIX_ACL = force yes;
  # ext4 metadata checksums need crc32c at *mount* time.  In this
  # initrdless setup there is no module loader before switch_root, so
  # it has to be built in (the nixpkgs default is =m).
  CRYPTO_CRC32C = force yes;
  DEVTMPFS = force yes;
  DEVTMPFS_MOUNT = force yes;

  # --- USB (xhci-tegra host, needed for keyboard/net after boot) ----------
  USB_SUPPORT = force yes;
  USB = force yes;
  USB_XHCI_HCD = force yes;
  USB_XHCI_TEGRA = force yes;
  PHY_TEGRA_XUSB = force yes;

  # --- Framebuffer console handed over by hboot ---------------------------
  VT = force yes;
  # NOTE: do NOT set FB_SIMPLE here. In Linux 7.2 FB_SIMPLE depends on
  # !DRM_SIMPLEDRM, and nixpkgs common-config already enables DRM_SIMPLEDRM=y,
  # which binds the same "simple-framebuffer" DT node (hboot hands over the
  # live DSI framebuffer). The console comes via DRM_FBDEV_EMULATION and
  # FRAMEBUFFER_CONSOLE (both already enabled by common-config).

  # --- Peripherals --------------------------------------------------------
  # I2C (Tegra I2C is selected by drivers; keep explicit)
  I2C = force yes;
  I2C_TEGRA = force yes;
  SPI = force yes;
  SPI_TEGRA114 = force yes;

  # PMIC (TPS65913/Palmas), charger (BQ24192), fuel gauge (MAX17050)
  MFD_PALMAS = force yes;
  REGULATOR_PALMAS = force yes;
  BATTERY_MAX17042 = force yes;
  POWER_SUPPLY = force yes;
  CHARGER_BQ24190 = force yes;
  EXTCON = force yes;
  EXTCON_USB_GPIO = force yes;

  # Keys / vibrator / touch
  KEYBOARD_GPIO = force yes;
  INPUT_GPIO_VIBRA = force module; # renamed from INPUT_GPIO_VIBRATOR
  RMI4_CORE = force module;
  RMI4_SPI = force module;

  # USB keyboard/storage: useful even without loadable drivers in the
  # initramfs (modules are loaded by udevd from the rootfs).
  USB_HID = force yes;
  HID_GENERIC = force yes;
  USB_STORAGE = force yes;
  VFAT_FS = force yes;
  NLS_CODEPAGE_437 = force yes;
  NLS_ISO8859_1 = force yes;

  # Watchdog: the tegra watchdog is not enabled in the device tree on
  # purpose -- hboot enables it with a 120s heartbeat and nothing
  # guarantees a userspace watchdog daemon on a fresh install.
  # TEGRA watchdog core stays available for later experimentation.
}
