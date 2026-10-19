# NixOS hardware module for the HTC Nexus 9 (flounder).
#
# This is the heart of the port: custom mainline kernel (with a new
# flounder device tree), initrdless boot via a tiny busybox initramfs,
# an Android boot image for hboot, and an ext4 rootfs image for the
# UDA partition.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  flounderKernel = pkgs.linuxKernel.kernels.linux_latest.override {
    kernelPatches = [
      {
        name = "flounder-dts";
        patch = ../kernel/0001-arm64-dts-nvidia-Add-support-for-the-HTC-Nexus-9-flounder.patch;
      }
      # Note: linux_latest already carries bridge_stp_helper and
      # request_key_helper (see pkgs/top-level/linux-kernels.nix); do
      # not add them again.
    ];
    structuredExtraConfig = (import ../kernel/kernel-config.nix) { inherit lib; };

    # We disable CONFIG_RUST (no Rust drivers on this board, and it saves
    # a ~700 MiB toolchain download). common-config.nix unconditionally
    # contributes RUST/DRM_NOVA/NOVA_CORE/DRM_PANIC_SCREEN_QR_CODE settings
    # whose Kconfig prompts then disappear (they depend on RUST), which
    # would be fatal "unused option" errors otherwise.
    ignoreConfigErrors = true;
  };

  flounderInitramfs = pkgs.callPackage ../nix/flounder-initramfs.nix { };

  mkBootImage =
    args:
    pkgs.callPackage ../nix/flounder-bootimg.nix (
      {
        kernel = config.boot.kernelPackages.kernel;
        initramfs = flounderInitramfs;
      }
      // args
    );

  rootfsImage =
    args:
    pkgs.callPackage ../nix/flounder-rootfs.nix (
      {
        toplevel = config.system.build.toplevel;
      }
      // args
    );

  # Kernel command line baked into the boot image. hboot appends its
  # own parameters (androidboot.*, carveouts, ...) to these.
  # console=tty0 last: it becomes /dev/console (getty), while kernel
  # messages still go to both the serial port and the framebuffer.
  bootCmdline = "earlycon=uart8250,mmio32,0x70006000 console=ttyS0,115200n8 console=tty0 no_console_suspend root=/dev/mmcblk0p31 rw";

  # Small helper script for the device: re-flash the boot partition
  # from a running system, so `nixos-rebuild switch` can update the
  # kernel without a host computer.
  flashBootScript = pkgs.writeShellScriptBin "flounder-flash-boot" ''
    set -euo pipefail
    img=${config.system.build.bootimg}
    echo "Writing $img ($(stat -c %s "$img") bytes) to /dev/mmcblk0p16 (LNX)..."
    dd if="$img" of=/dev/mmcblk0p16 bs=1M conv=fsync
    echo "Done. The new kernel boots on the next reboot."
  '';
in
{
  # --- Cross-compile from x86_64 (the host running this flake) ------------
  nixpkgs.hostPlatform = "aarch64-linux";
  # The machine running this flake is x86_64; build the aarch64 closure
  # with a cross stdenv instead of emulation.
  nixpkgs.buildPlatform = "x86_64-linux";

  # --- Boot chain ----------------------------------------------------------
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = false;
  boot.loader.systemd-boot.enable = false;

  # Our own tiny initramfs lives in the Android boot image; the NixOS
  # stage-1 initrd would never fit into the 32 MiB boot partition.
  boot.initrd.enable = false;

  boot.kernelPackages = pkgs.linuxPackagesFor flounderKernel;
  boot.kernelParams = [
    "earlycon=uart8250,mmio32,0x70006000"
    "console=ttyS0,115200n8"
    "console=tty0"
    "no_console_suspend"
    "root=/dev/mmcblk0p31"
    "rw"
  ];

  boot.consoleLogLevel = 7;
  boot.kernel.sysctl = {
    "kernel.printk" = "7 4 1 7"; # keep early boot noise on the serial console
  };

  # --- Root filesystem: UDA partition, ext4, grows to partition size ------
  fileSystems."/" = {
    device = "/dev/mmcblk0p31";
    fsType = "ext4";
    options = [
      "x-systemd.growfs"
      "noatime"
    ];
  };

  swapDevices = [ ];

  hardware.deviceTree.enable = false; # dtb is appended to the kernel image

  # --- Build products ------------------------------------------------------
  system.build = {
    # The 7.2 Image decompresses to ~69 MiB.  hboot maps the boot
    # header addresses with a +0x70000000 DRAM offset and puts the
    # ramdisk at 0x11000000 (-> 0x81000000), which the default kernel
    # load address (0x10008000 -> 0x80008000) would overwrite.
    # Load the kernel at 0x20008000 (-> 0x90008000) instead; the
    # ramdisk stays at the hboot-default 0x11000000.
    bootimg = mkBootImage {
      cmdline = bootCmdline;
      kernelOffset = "0x10008000";  # base 0x10000000 -> 0x20008000
      ramdiskOffset = "0x01000000"; # -> 0x11000000
    };
    bootimg-highmem = mkBootImage {
      cmdline = bootCmdline;
      kernelOffset = "0x10008000";
      ramdiskOffset = "0x01000000";
    };
    bootimg-rescue = mkBootImage {
      # Boots straight into a shell in the initramfs (kernel init=
      # applies to the initramfs), for debugging without a rootfs.
      cmdline = bootCmdline + " init=/bin/sh";
      kernelOffset = "0x10008000";
      ramdiskOffset = "0x01000000";
    };
    rootfs-image = rootfsImage { };
  };

  # On-device kernel updates: `flounder-flash-boot` writes the freshly
  # built boot.img to the LNX partition.
  environment.systemPackages = [ flashBootScript ];

  # The rootfs image is built with mkfs.ext4, not by nixos-install, so
  # there is no Nix database yet.  Load the registration file that
  # flounder-rootfs.nix put at /nix-path-registration on first boot.
  # (Same idea as nixos/modules/installer/sd-card/sd-image.nix.)
  systemd.services.register-nix-paths = {
    description = "Register Nix store paths from the rootfs image";
    unitConfig = {
      DefaultDependencies = false;
      ConditionPathExists = "/nix-path-registration";
    };
    wantedBy = [ "sysinit.target" ];
    before = [
      "sysinit.target"
      "shutdown.target"
      "nix-daemon.socket"
      "nix-daemon.service"
    ];
    after = [ "local-fs.target" ];
    conflicts = [ "shutdown.target" ];
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${config.nix.package}/bin/nix-store --load-db < /nix-path-registration

      # nixos-rebuild requires a system profile and the /etc/NIXOS tag.
      touch /etc/NIXOS
      ${config.nix.package}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system

      rm -f /nix-path-registration
    '';
  };

  # --- Peripherals ---------------------------------------------------------

  # eMMC and SDHCI are built-in; no module loading needed at boot.
  boot.initrd.availableKernelModules = [ ];
  boot.initrd.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # Tegra SoC temperature.
  hardware.enableRedistributableFirmware = lib.mkDefault false;

  networking.wireless.enable = false; # brcmfmac firmware TODO, see docs

  # Denver runs at a fixed frequency until DFLL support is ported.
  powerManagement.cpuFreqGovernor = "schedutil";
}
