#!/usr/bin/env bash
# Test-boot the built image WITHOUT flashing anything.
#
# hboot supports `fastboot boot`, so you can iterate freely: a reboot
# brings you straight back to whatever is in the boot partition.
#
# Prerequisites: device in bootloader mode (Vol-Down + Power), watch
# the serial console on the board's UART test points at 115200 8N1.

set -euo pipefail
cd "$(dirname "$0")/.."

IMG=${1:-out/boot.img}

fastboot boot "$IMG"
echo
echo "Boot image handed to hboot. Watch the serial console:"
echo "  console=ttyS0,115200 (see docs/flounder-hboot-analysis.md for the test points)"
