#!/usr/bin/env bash
# Build all flashable artifacts for the flounder NixOS port.
#
#   out/boot.img       – Android boot image (kernel + dtb + initramfs)
#   out/rootfs.img     – ext4 NixOS rootfs for the UDA partition
#   out/bootimg-rescue – boot image that drops into an initramfs shell
#
# Everything is cross-compiled from x86_64; no emulation needed.

set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p out

NIX_FLAGS=(--extra-experimental-features 'nix-command flakes')

echo "==> building boot.img (kernel + dtb + initramfs)"
nix "${NIX_FLAGS[@]}" build .#bootimg -o out/boot.img.tmp
mv -T out/boot.img.tmp out/boot.img

echo "==> building rescue boot image"
nix "${NIX_FLAGS[@]}" build .#bootimg-rescue -o out/bootimg-rescue.tmp
mv -T out/bootimg-rescue.tmp out/bootimg-rescue

echo "==> building rootfs image (this evaluates/builds the full closure)"
nix "${NIX_FLAGS[@]}" build .#rootfs-image -o out/rootfs.img.tmp
mv -T out/rootfs.img.tmp out/rootfs.img

echo
echo "Artifacts:"
ls -l out/boot.img out/bootimg-rescue out/rootfs.img
echo
echo "Next: scripts/flash-test-boot.sh  (safe, temporary boot via fastboot)"
