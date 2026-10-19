#!/bin/sh
# /init for the flounder initramfs.
#
# Mounts the NixOS root filesystem (UDA partition, /dev/mmcblk0p31)
# and switch_roots into the system closure. Falls back to a rescue
# shell on the serial console (ttyS0) if anything goes wrong.

export PATH=/bin

rescue() {
    echo ""
    echo "!!! flounder initramfs: $1"
    echo "!!! Dropping to a rescue shell (ttyS0)."
    echo "!!! Useful: mount -t ext4 /dev/mmcblk0p31 /mnt"
    exec setsid sh -c 'exec sh </dev/ttyS0 >/dev/ttyS0 2>&1'
}

mkdir -p /proc /sys /dev /mnt
mount -t proc proc /proc || rescue "cannot mount /proc"
mount -t sysfs sysfs /sys || rescue "cannot mount /sys"
mount -t devtmpfs devtmpfs /dev || rescue "cannot mount /dev"

echo "flounder: initramfs up, waiting for eMMC (/dev/mmcblk0p31)..."

# Wait up to 15 s for the eMMC device to appear.
i=0
while [ ! -b /dev/mmcblk0p31 ]; do
    i=$((i + 1))
    [ $i -gt 30 ] && rescue "mmcblk0p31 never showed up"
    sleep 0.5
done

echo "flounder: mounting root..."
mount -t ext4 -o rw /dev/mmcblk0p31 /mnt || rescue "mount /dev/mmcblk0p31 failed"

[ -x /mnt/nix/var/nix/profiles/system/init ] || rescue "no NixOS system on rootfs"

umount /proc /sys
exec switch_root /mnt /nix/var/nix/profiles/system/init
