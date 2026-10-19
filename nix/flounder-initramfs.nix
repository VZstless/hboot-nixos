# Tiny busybox initramfs for the HTC Nexus 9 (flounder).
#
# Why a custom initramfs instead of the NixOS stage-1 initrd:
#   * The LNX (boot) partition is only 32 MiB. A stock NixOS initrd
#     (systemd-udevd, kmod, ... plus modules) does not fit next to a
#     mainline kernel image.
#   * All drivers needed to mount the root filesystem are built into
#     the kernel, so stage-1's only real job is: mount UDA, switch_root.
#   * A rescue shell on ttyS0 is priceless during bring-up.
#
# The resulting cpio.gz is ~3 MiB.

{
  lib,
  pkgsStatic,
  runCommand,
  cpio,
  gzip,
}:

let
  busybox = pkgsStatic.busybox;

  init = ./flounder-init.sh;
in
runCommand "flounder-initramfs.cpio.gz"
  {
    nativeBuildInputs = [
      cpio
      gzip
    ];
    # The busybox closure is needed inside the sandbox to copy it over.
    buildInputs = [ busybox ];
  }
  ''
    (
      mkdir -p root/bin root/dev root/proc root/sys root/mnt
      cp -a ${busybox}/bin/busybox root/bin/
      ln -s /bin/busybox root/bin/sh
      install -m 0755 ${init} root/init

      # deterministic archive
    )
    (cd root && find . -print0 | cpio -0 -o -H newc --owner +0:+0) | gzip -9n > $out
  ''
