#!/usr/bin/env bash
# Flash the boot image to the LNX partition ("boot").
#
# Only do this after flash-test-boot.sh has proven the image boots!
# If it goes wrong, you can always rescue with `fastboot boot` or the
# TWRP image (hboot itself lives outside of any flashable partition
# here and cannot be bricked through LNX).

set -euo pipefail
cd "$(dirname "$0")/.."

IMG=${1:-out/boot.img}

SIZE=$(stat -c %s "$IMG")
LIMIT=$((32 * 1024 * 1024))
if [ "$SIZE" -ge "$LIMIT" ]; then
    echo "boot.img is $SIZE bytes, exceeds the 32 MiB LNX partition!" >&2
    exit 1
fi

echo "Flashing $IMG ($SIZE bytes) to LNX (boot)..."
fastboot flash boot "$IMG"
echo "Done. Rebooting:"
fastboot reboot
