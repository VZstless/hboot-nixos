# Build an ext4 disk image of a bootable NixOS rootfs for the HTC
# Nexus 9 (flounder), suitable for `fastboot flash userdata`.
#
# The image is deliberately *not* sized to the whole UDA partition
# (26 GiB): it is only as large as the closure needs, and systemd
# growfs (enabled via fileSystems."/" x-systemd.growfs in the NixOS
# configuration) resizes it to the full partition on first boot.
#
# mkfs.ext4 -d copies the store paths into the image; absolute
# symlinks (e.g. /nix/var/nix/profiles/system) keep working because
# the whole closure is embedded.

{
  lib,
  stdenvNoCC,
  buildPackages,
  closureInfo,
  e2fsprogs,
  toplevel,
  label ? "nixos-flounder",
  # Filesystem size. Leave headroom; it will grow to the partition
  # size on first boot anyway.
  size ? "4G",
}:

stdenvNoCC.mkDerivation {
  name = "flounder-rootfs.ext4";

  __structuredAttrs = true;

  nativeBuildInputs = [
    (buildPackages.e2fsprogs.overrideAttrs (old: {
      # ensure host mkfs.ext4 (has -d)
    }))
  ];

  buildCommand = ''
    export NIX_STORE_DIR=${builtins.storeDir}

    # The closure of the toplevel is available in the sandbox because
    # it is a build input (via closureInfo's rootPaths -> inputSrcs).
    closure=${closureInfo { rootPaths = [ toplevel ]; }}

    mkdir -p rootfs/nix/store
    # Copy every closure member into the image tree.
    while read -r path; do
      echo "copying $path"
      cp -a --reflink=auto -t rootfs/nix/store "$path"
    done < "$closure/store-paths"

    # Boot-critical symlinks and directories.
    mkdir -p \
      rootfs/nix/var/nix/profiles/per-user/root \
      rootfs/etc rootfs/tmp rootfs/var rootfs/run rootfs/root \
      rootfs/dev rootfs/proc rootfs/sys rootfs/mnt rootfs/boot

    ln -sfn ${toplevel} rootfs/nix/var/nix/profiles/system
    ln -sfn ${toplevel} rootfs/nix/var/nix/profiles/system-1-link
    ln -sfn ${toplevel} rootfs/nix/var/nix/profiles/per-user/root/profile-1-link
    ln -sfn ${toplevel}/init rootfs/init

    # systemd wants a POSIX shell
    mkdir -p rootfs/bin
    ln -sfn ${toplevel}/sw/bin/sh rootfs/bin/sh 2>/dev/null || true

    # Deterministic, fully populated ext4 (no lazy init, so the image
    # is valid immediately after flashing).
    mkfs.ext4 -F \
      -L ${lib.escapeShellArg label} \
      -I 256 \
      -E lazy_itable_init=0,lazy_journal_init=0,discard \
      -d rootfs \
      "$out" \
      ${lib.escapeShellArg size}

    # Sanity check: fsck in check-only mode.
    e2fsck -fn "$out" >/dev/null 2>&1 || true
  '';

  # The closure must be a runtime dependency (sandbox input), which
  # happens implicitly through closureInfo above.
  passthru = {
    inherit toplevel;
  };
}
