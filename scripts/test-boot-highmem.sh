#!/usr/bin/env bash
# Experiment: load the kernel at 0x20008000 (0x90008000 in RAM after
# hboot's +0x70000000 alias), above the ramdisk at 0x11000000.
#
# If hboot honours the kernel_addr field in the Android boot image
# header, this avoids the 7.2 Image (~69 MiB decompressed) overwriting
# the initramfs at 0x81000000.
set -euo pipefail
cd "$(dirname "$0")/.."
IMG=${1:-out/boot-highmem.img}
[ -f "$IMG" ] || { echo "missing $IMG (build .#bootimg-highmem)" >&2; exit 1; }
fastboot boot "$IMG"
