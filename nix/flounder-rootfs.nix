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
# the whole closure is embedded.  fakeroot is used so the files in the
# image are owned by root:root even though the Nix builder is not root.
#
# /nix-path-registration is included so the first boot can populate
# the Nix database (`nix-store --load-db`); see the
# register-nix-paths service in configuration/flounder-hardware.nix.

{
  lib,
  stdenvNoCC,
  buildPackages,
  closureInfo,
  toplevel,
  label ? "nixos-flounder",
  # Filesystem size.  The image grows to the partition size on first
  # boot anyway; 4 GiB keeps `fastboot flash` reasonably quick.
  size ? "4G",
}:

stdenvNoCC.mkDerivation {
  name = "flounder-rootfs.ext4";

  __structuredAttrs = true;

  nativeBuildInputs = [
    buildPackages.e2fsprogs.bin
    buildPackages.fakeroot
  ];

  buildCommand = ''
    export NIX_STORE_DIR=${builtins.storeDir}

    closure=${closureInfo { rootPaths = [ toplevel ]; }}

    mkdir -p rootfs/nix/store
    while read -r path; do
      echo "copying $path"
      cp -a --reflink=auto -t rootfs/nix/store "$path"
    done < "$closure/store-paths"

    # Boot-critical directories and profile symlinks.
    mkdir -p \
      rootfs/nix/var/nix/profiles/per-user/root \
      rootfs/etc rootfs/tmp rootfs/var rootfs/run rootfs/root \
      rootfs/dev rootfs/proc rootfs/sys rootfs/mnt rootfs/boot

    ln -sfn ${toplevel} rootfs/nix/var/nix/profiles/system
    ln -sfn ${toplevel} rootfs/nix/var/nix/profiles/system-1-link
    ln -sfn ${toplevel} rootfs/init

    # Used by register-nix-paths.service on first boot to load the Nix
    # database (the image is built outside of `nixos-install`).
    cp "$closure/registration" rootfs/nix-path-registration

    # Sanity check on the amount of data: leave at least ~200 MiB of
    # slack in the 4 GiB image.
    used=$(du -s -B1 --apparent-size rootfs | cut -f1)
    echo "rootfs payload: $used bytes"
    if [ "$used" -gt 3800000000 ]; then
      echo "ERROR: rootfs payload ($used bytes) does not fit in $size" >&2
      exit 1
    fi

    # -i 8192: a NixOS closure has many small files (default 16k/inode
    # can run out of inodes).  -E lazy_*_init=0 makes the image valid
    # immediately after flashing, without a first-boot fsck.
    fakeroot mkfs.ext4 -F \
      -L ${lib.escapeShellArg label} \
      -I 256 \
      -i 8192 \
      -E lazy_itable_init=0,lazy_journal_init=0,discard \
      -d rootfs \
      "$out" \
      ${lib.escapeShellArg size}

    # Check-only fsck: a corrupted image should fail the build, not the
    # device.  (-f forces a full check.)
    e2fsck -fn -f "$out"
  '';

  passthru = {
    inherit toplevel;
  };
}
