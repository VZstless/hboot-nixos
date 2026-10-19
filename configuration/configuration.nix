# NixOS 26.11-unstable configuration for the HTC Nexus 9 (flounder).
#
# Minimal but usable: serial console, USB (host), sshd once networking
# exists. Everything device-specific lives in flounder-hardware.nix.

{ config, pkgs, lib, ... }:

{
  imports = [
    ./flounder-hardware.nix
  ];

  system.stateVersion = "26.11";

  # No man pages / HTML manual on an embedded tablet: they pull in
  # texinfo, man-db, w3m, perl modules, ... and make the cross-built
  # closure needlessly large.  `nixos-help` is unavailable; the docs
  # for the port live in this repository.
  documentation.enable = false;

  # --- Users ---------------------------------------------------------------
  users.users.root = {
    initialPassword = "flounder"; # change me after first login
    openssh.authorizedKeys.keys = [
      # Put your SSH key here so you can log in once USB/WiFi works:
      # "ssh-ed25519 AAAA... user@host"
    ];
  };

  # --- Networking -----------------------------------------------------------
  networking.hostName = "flounder";
  networking.useDHCP = false; # no ethernet yet; wifi is TODO (see docs)
  networking.firewall.enable = false;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # --- Console ---------------------------------------------------------------
  # Serial debug console (board test points, see
  # docs/flounder-hboot-analysis.md). Also a getty on the simplefb
  # console, since hboot hands over a working framebuffer.
  services.getty.autologinUser = "root";
  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    # Tegra UART is quirky after suspend; keep it alive.
    serviceConfig.Restart = "always";
  };

  # --- Software --------------------------------------------------------------
  environment.systemPackages = with pkgs; [
    vim
    htop
    usbutils
    pciutils
    ethtool
    # iwd/iw are intentionally absent until the BCM4354 firmware and
    # NVRAM are available (see docs/porting-process.md, TODO).
  ];

  # No desktop on the first iteration. The simple-framebuffer console
  # works; real display support via tegra-drm is future work.
  services.xserver.enable = false;

  # --- Misc ------------------------------------------------------------------
  # Journald to RAM only -- the eMMC is soldered, be gentle.
  services.journald.settings.Journal = {
    Storage = "volatile"; # journald to RAM only: the eMMC is soldered, be gentle
    RuntimeMaxUse = "64M";
  };

  # The flake's nixpkgs input is a path to the local checkout; NixOS
  # would otherwise put the whole ~4.5 GiB nixpkgs tree into
  # /etc/nix/registry.json and therefore into the rootfs closure.
  # We do not need an on-device nixpkgs registry for this port.
  nix.registry = lib.mkForce { };

  nix.settings.trusted-users = [ "root" ];
  nix.extraOptions = ''
    # store optimisation saves a lot of space on a 26 GiB partition
    auto-optimise-store = true
  '';
}
