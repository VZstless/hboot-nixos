#!/usr/bin/env bash
# Flash the NixOS rootfs image to the UDA partition ("userdata").
#
# Default/working method: TWRP + adb push directly to the block device.
# This writes every byte of the 4 GiB image.  `fastboot flash userdata`
# is *not* reliable here: its automatic sparse conversion skips zero
# blocks, leaving old data in the partition and corrupting ext4 block
# bitmaps (observed as "bad block bitmap checksum" and a missing NixOS
# system profile).
#
#   twrp      – boot TWRP temporarily, adb push the image to
#               /dev/block/mmcblk0p31, sync, reboot to bootloader.
#               Takes ~8 minutes over USB2.  (default)
#   fastboot  – kept for reference only; may corrupt the filesystem.
#
# WARNING: this wipes the userdata (UDA) partition completely.

set -euo pipefail
cd "$(dirname "$0")/.."

IMG=${1:-out/rootfs.img}
METHOD=${2:-twrp}
TWRP=${TWRP:-hboot-analysis/twrp-flounder.img}

[ -f "$IMG" ] || { echo "no image at $IMG (run scripts/build-all.sh)" >&2; exit 1; }

flash_twrp() {
    echo "Temporarily booting TWRP..."
    fastboot boot "$TWRP"

    echo "Waiting for TWRP (adb)..."
    adb wait-for-device
    sleep 10

    echo "Unmounting UDA (if TWRP mounted it)..."
    adb shell 'umount /data 2>/dev/null; umount /sdcard 2>/dev/null; umount /dev/block/mmcblk0p31 2>/dev/null; true' || true

    echo "Writing $IMG directly to /dev/block/mmcblk0p31 (raw, ~8 min)..."
    # adb push to a block device writes all bytes (no sparse skipping).
    time adb push "$IMG" /dev/block/mmcblk0p31
    adb shell sync

    echo "Rootfs written. Reboot to bootloader."
    adb reboot bootloader
}

flash_fastboot() {
    echo "WARNING: fastboot sparse flashing corrupted the rootfs in testing." >&2
    echo "         Prefer: $0 $IMG twrp" >&2
    echo "Flashing $IMG to UDA (userdata)..."
    fastboot flash userdata "$IMG"
}

case "$METHOD" in
    twrp|auto) flash_twrp ;;
    fastboot)  flash_fastboot ;;
    *) echo "unknown method: $METHOD (use twrp|fastboot)" >&2; exit 1 ;;
esac

echo
echo "Done. Now flash the boot image:"
echo "  scripts/flash-boot.sh"
echo "and reconnect a USB OTG keyboard or UART for console access."
