#!/usr/bin/env bash
# Build all flashable artifacts for the flounder NixOS port.
#
#   out/boot.img       – Android boot image (kernel + dtb + initramfs)
#   out/rootfs.img     – ext4 NixOS rootfs for the UDA partition
#   out/bootimg-rescue – boot image that drops into an initramfs shell
#
# Everything is cross-compiled from x86_64; no emulation needed.
#
# The first full run has to cross-build the aarch64 userland that is not
# in cache.nixos.org (Hydra does not build cross outputs), which takes a
# while.  NIX_MAX_JOBS can be used to control parallelism, e.g.:
#   NIX_MAX_JOBS=6 scripts/build-all.sh

set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p out

NIX_FLAGS=(
  --extra-experimental-features 'nix-command flakes'
  --max-jobs "${NIX_MAX_JOBS:-4}"
  --cores "${NIX_CORES:-2}"
)
LOG_DIR=${LOG_DIR:-out/logs}
mkdir -p "$LOG_DIR"

build() {
  local attr=$1 out=$2 log="$LOG_DIR/$(basename "$2").log"
  echo "==> building $attr  (log: $log)"
  if ! nix "${NIX_FLAGS[@]}" build ".#$attr" -o "$out.tmp" >"$log" 2>&1; then
    echo "!!! build of $attr failed; last 40 log lines:" >&2
    tail -40 "$log" >&2
    exit 1
  fi
  # nix build leaves a symlink into /nix/store; keep a real copy in out/
  # so the artifacts survive a garbage collection.
  rm -f "$out"
  cp -L --reflink=auto "$out.tmp" "$out"
  rm -f "$out.tmp"
  ls -l "$out"
}

build bootimg         out/boot.img
build bootimg-rescue  out/bootimg-rescue
# Experimental layout: kernel above the ramdisk (see
# docs/build-and-verification.md section 4).
build bootimg-highmem out/boot-highmem.img
build rootfs-image    out/rootfs.img

echo
echo "Artifacts:"
ls -l out/boot.img out/bootimg-rescue out/rootfs.img
echo
echo "Next: scripts/flash-test-boot.sh  (safe, temporary boot via fastboot)"
