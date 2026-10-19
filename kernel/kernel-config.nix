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

  # --- Boot path: serial console, eMMC, ext4 (all built-in) ---------------
  SERIAL_8250 = force yes;
  SERIAL_8250_TEGRA = force yes; # deprecated alias, harmless
  SERIAL_TEGRA = force yes;
  MMC = force yes;
  MMC_SDHCI = force yes;
  MMC_SDHCI_TEGRA = force yes;
  EXT4_FS = force yes;
  EXT4_FS_POSIX_ACL = force yes;
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

  # Watchdog: the tegra watchdog is not enabled in the device tree on
  # purpose -- hboot enables it with a 120s heartbeat and nothing
  # guarantees a userspace watchdog daemon on a fresh install.
  # TEGRA watchdog core stays available for later experimentation.
}
