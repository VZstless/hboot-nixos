#!/bin/sh
# /init for the flounder initramfs.
#
# Mounts the NixOS root filesystem (UDA partition, /dev/mmcblk0p31)
# and switch_roots into the system closure. Falls back to a rescue
# shell on the serial console (ttyS0) if anything goes wrong.

export PATH=/bin:/sbin

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

echo "flounder: initramfs up"
echo "flounder: cmdline: $(cat /proc/cmdline)"
echo "flounder: waiting for eMMC (/dev/mmcblk0p31)..."

# Wait up to 15 s for the eMMC partition to appear, then fall back to
# the UDA loop offset below if the GPT was not parsed.
i=0
while [ ! -b /dev/mmcblk0p31 ] && [ $i -lt 30 ]; do
    i=$((i + 1))
    sleep 0.5
done

if [ -b /dev/mmcblk0p31 ]; then
    echo "flounder: mounting /dev/mmcblk0p31..."
    mount -t ext4 -o rw /dev/mmcblk0p31 /mnt || rescue "mount /dev/mmcblk0p31 failed"
else
    # hboot's GPT lives at LBA 69631 and the mainline GPT parser may
    # not see it.  Fall back to the known UDA offset (7299072 * 512).
    echo "flounder: p31 missing, mounting UDA via loop offset..."
    [ -e /dev/loop0 ] || mknod /dev/loop0 b 7 0
    losetup -o 3737124864 /dev/loop0 /dev/mmcblk0 || rescue "losetup failed"
    mount -t ext4 -o rw /dev/loop0 /mnt || rescue "mount /dev/loop0 failed"
fi

# /nix/var/nix/profiles/system is an absolute symlink.  Resolve it
# inside the mounted rootfs, not against the initramfs root.
target=$(readlink /mnt/nix/var/nix/profiles/system 2>/dev/null)
case "$target" in
    /*) initpath="/mnt$target/init" ;;
    ?*) initpath="/mnt/nix/var/nix/profiles/$target/init" ;;
    *)  initpath="" ;;
esac
if [ -n "$initpath" ] && [ -x "$initpath" ]; then
    echo "flounder: NixOS system found: $target"
else
    echo "flounder: rootfs check failed (target='$target')"
    ls -l /mnt/nix/var/nix/profiles/system 2>&1
    rescue "no NixOS system on rootfs"
fi

umount /proc /sys
exec switch_root /mnt /nix/var/nix/profiles/system/init
