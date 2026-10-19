#!/usr/bin/env bash
# Restore the original LNX (boot) partition from the dump in
# hboot-analysis/LNX.img and reboot.
#
# Use this if a test kernel leaves the device unbootable.  hboot itself
# is not touched, so `fastboot` remains available.
set -euo pipefail
cd "$(dirname "$0")/.."

IMG=${1:-hboot-analysis/LNX.img}
[ -f "$IMG" ] || { echo "missing $IMG" >&2; exit 1; }

echo "Restoring $IMG to the LNX (boot) partition..."
fastboot flash boot "$IMG"
echo "Done. Rebooting."
fastboot reboot
