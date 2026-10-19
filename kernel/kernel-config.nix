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

{ lib, ... }:

with lib.kernel;

{
  # --- SoC / platform -----------------------------------------------------
  ARCH_TEGRA = yes;
  ARCH_TEGRA_132_SOC = yes;
  PINCTRL_TEGRA124 = yes;
  TEGRA_SOCTHERM = yes;
  TEGRA20_APB_DMA = yes;

  # --- Boot path: serial console, eMMC, ext4 (all built-in) ---------------
  SERIAL_8250 = yes;
  SERIAL_8250_TEGRA = yes; # deprecated alias, harmless
  SERIAL_8250_EARLYCON = yes;
  SERIAL_TEGRA = yes;
  MMC = yes;
  MMC_SDHCI = yes;
  MMC_SDHCI_TEGRA = yes;
  EXT4_FS = yes;
  EXT4_FS_POSIX_ACL = yes;
  DEVTMPFS = yes;
  DEVTMPFS_MOUNT = yes;

  # --- USB (xhci-tegra host, needed for keyboard/net after boot) ----------
  USB_SUPPORT = yes;
  USB = yes;
  USB_XHCI_HCD = yes;
  USB_XHCI_TEGRA = yes;
  PHY_TEGRA_XUSB = yes;

  # --- Framebuffer console handed over by hboot ---------------------------
  VT = yes;
  FB = yes;
  FB_SIMPLE = yes;
  FRAMEBUFFER_CONSOLE = yes;
  FRAMEBUFFER_CONSOLE_DETECT_PRIMARY = yes;

  # --- Peripherals --------------------------------------------------------
  # I2C (Tegra I2C is selected by drivers; keep explicit)
  I2C = yes;
  I2C_TEGRA = yes;
  SPI = yes;
  SPI_TEGRA114 = yes;

  # PMIC (TPS65913/Palmas), charger (BQ24192), fuel gauge (MAX17050)
  MFD_PALMAS = yes;
  REGULATOR_PALMAS = yes;
  BATTERY_MAX17042 = yes;
  POWER_SUPPLY = yes;
  CHARGER_BQ24190 = yes;
  EXTCON = yes;
  EXTCON_USB_GPIO = yes;

  # Keys / vibrator / touch
  KEYBOARD_GPIO = yes;
  INPUT_GPIO_VIBRATOR = module;
  RMI4_CORE = module;
  RMI4_SPI = module;

  # Watchdog: the tegra watchdog is not enabled in the device tree on
  # purpose -- hboot enables it with a 120s heartbeat and nothing
  # guarantees a userspace watchdog daemon on a fresh install.
  # TEGRA watchdog core stays available for later experimentation.
}
