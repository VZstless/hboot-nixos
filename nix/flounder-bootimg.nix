# Build an Android boot image for the HTC Nexus 9 (flounder).
#
# Boot chain facts (see docs/flounder-hboot-analysis.md):
#   * hboot loads the kernel from the LNX partition ("boot") as an
#     Android boot image v0 and *does* decompress gzip kernels
#     (verified: the shipped postmarketOS image boots Image.gz + dtb).
#   * The device tree is NOT read from the (zeroed) DTB partition; it
#     must be appended after the gzip stream: `Image.gz` ++ `dtb`.
#   * Load addresses per the original LNX image:
#       base 0x10000000, kernel +0x00008000, ramdisk +0x01000000,
#       tags +0x00000100, page size 2048, header v0.
#   * hboot injects its own cmdline (androidboot.*, memory carveouts,
#     gpt_sector, ...); everything in --cmdline below is passed through
#     and merged with it.

{
  lib,
  runCommand,
  gzip,
  mkbootimg-osm0sis,
  kernel,
  dtb ? "${kernel}/dtbs/nvidia/tegra132-flounder.dtb",
  initramfs,
  cmdline ? "",
}:

runCommand "flounder-boot.img"
  {
    nativeBuildInputs = [
      gzip
      mkbootimg-osm0sis
    ];
  }
  ''
    echo "assembling flounder boot image"

    # Image.gz + appended dtb (Tegra Android convention)
    gzip -9n -c ${kernel}/Image > kernel.gz
    cat kernel.gz ${dtb} > kernel-dtb

    mkbootimg \
      --kernel kernel-dtb \
      --ramdisk ${initramfs} \
      --base 0x10000000 \
      --kernel_offset 0x00008000 \
      --ramdisk_offset 0x01000000 \
      --tags_offset 0x00000100 \
      --pagesize 2048 \
      --header_version 0 \
      --cmdline "${lib.escapeShellArg cmdline}" \
      -o $out

    # The LNX partition is 32 MiB; fail loudly if we outgrow it.
    size=$(stat -c %s $out)
    if [ "$size" -ge $((32 * 1024 * 1024)) ]; then
      echo "ERROR: boot image is $size bytes, LNX partition is 33554432 bytes" >&2
      exit 1
    fi
    echo "boot image size: $size bytes (LNX: 33554432)"
  ''
