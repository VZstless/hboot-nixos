# NixOS 26.11-unstable configuration for the HTC Nexus 9 (flounder).
#
# Minimal but usable: serial console, USB CDC ACM/ECM, and sshd over the
# USB network link. Everything device-specific lives in flounder-hardware.nix.

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
  networking.useDHCP = false;
  # The built-in CDC composite gadget exposes a stable point-to-point link.
  # The host side should use 192.168.77.1/30 and can then SSH to this address.
  networking.interfaces.usb0 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "192.168.77.2";
        prefixLength = 30;
      }
    ];
  };
  networking.firewall.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
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
  # USB CDC ACM appears as /dev/ttyACM0 on the host and /dev/ttyGS0 here.
  systemd.services."serial-getty@ttyGS0" = {
    enable = true;
    serviceConfig.Restart = "always";
  };

  # --- Software --------------------------------------------------------------
  environment.systemPackages =
    let
      # fastfetch enables optional Enlightenment support in its upstream
      # build inputs even when the wrapper does not use that feature.  EFL's
      # eolian_gen is a target executable, so it cannot be built for this
      # cross-compilation without a separate native-tool override.
      fastfetchUnwrapped = pkgs.fastfetch-unwrapped.overrideAttrs (old: {
        buildInputs = lib.remove pkgs.enlightenment.efl old.buildInputs;
      });
      fastfetch = pkgs.fastfetch.override {
        fastfetch-unwrapped = fastfetchUnwrapped;
      };
    in
    with pkgs; [
      vim
      htop
      usbutils
      pciutils
      ethtool
      fastfetch
      iw
      wpa_supplicant
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
