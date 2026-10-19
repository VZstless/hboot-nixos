#!/usr/bin/env bash
# Flash the NixOS rootfs image to the UDA partition ("userdata").
#
# Two methods, picked automatically / manually:
#
#   fastboot  – direct flash. Large raw images are converted to the
#               Android sparse format and streamed in chunks if the
#               bootloader's max-download-size is small. Needs
#               img2simg (android-tools / simg2img package).
#
#   twrp      – boot TWRP temporarily (fastboot boot twrp-flounder.img),
#               push the image, dd it to the partition from within
#               Android. Slow but works with any max-download-size.
#
# WARNING: this wipes the userdata partition completely.

set -euo pipefail
cd "$(dirname "$0")/.."

IMG=${1:-out/rootfs.img}
METHOD=${2:-auto}
TWRP=${TWRP:-hboot-analysis/twrp-flounder.img}

[ -f "$IMG" ] || { echo "no image at $IMG (run scripts/build-all.sh)" >&2; exit 1; }

flash_fastboot() {
    local src=$1
    local max
    max=$(fastboot getvar max-download-size 2>/dev/null | awk -F': ' '/max-download-size/ {print $2}' | tail -1)
    echo "max-download-size: ${max:-unknown}"
    if [ -n "${max:-}" ] && [ "$max" != "0x2000000000000000" ] && [ "$max" != "0" ] && [ "$((max))" -lt "$(stat -c %s "$src")" ] 2>/dev/null; then
        if command -v img2simg >/dev/null; then
            echo "converting to sparse image for chunked flashing..."
            img2simg "$src" "$src.sparse" 4096
            src="$src.sparse"
        else
            echo "img2simg not found and image exceeds max-download-size." >&2
            echo "Install android-tools (img2simg) or use: $0 $IMG twrp" >&2
            exit 1
        fi
    fi
    echo "Flashing $src to UDA (userdata)... (this can take a while)"
    fastboot flash userdata "$src"
    rm -f "$src.sparse"
}

flash_twrp() {
    echo "Temporarily booting TWRP..."
    fastboot boot "$TWRP"
    echo "Waiting for the device to come up in TWRP (adb)..."
    adb wait-for-device
    sleep 10
    echo "Pushing image (slow over adb)..."
    adb push "$IMG" /tmp/rootfs.img
    echo "Writing to /dev/block/mmcblk0p31 (UDA)..."
    adb shell "dd if=/tmp/rootfs.img of=/dev/block/mmcblk0p31 bs=4M conv=fsync"
    adb shell "sync"
    adb reboot bootloader
}

case "$METHOD" in
    fastboot) flash_fastboot "$IMG" ;;
    twrp)     flash_twrp ;;
    auto)     flash_fastboot "$IMG" ;;
    *) echo "unknown method: $METHOD (use fastboot|twrp|auto)" >&2; exit 1 ;;
esac

echo
echo "Done. Now flash the boot image (scripts/flash-boot.sh) and reboot."
