#!/usr/bin/env python3
"""Inspect an Android boot image (v0) built for the flounder port.

Checks performed:
  * Android boot image header fields and command line (detects the
    historical stray-quote bug);
  * kernel gzip member size and the appended Tegra DTB;
  * arm64 Image header (code0/code1, text_offset, image_size, magic);
  * whether the decompressed kernel overlaps the ramdisk load address;
  * ramdisk compression and number of cpio entries / applets.

Usage: scripts/analyze-bootimg.py out/boot.img
"""
import struct
import sys
import zlib
import gzip
import io


def u32(d, off):
    return struct.unpack_from("<I", d, off)[0]


def main(path):
    d = open(path, "rb").read()
    print(f"== {path} ({len(d)} bytes)")

    if d[:8] != b"ANDROID!":
        sys.exit("not an Android boot image (bad magic)")
    ks, ka, rs, ra, ss, sa, ta, ps, hv, osv = struct.unpack("<10I", d[8:48])
    name = d[48:64].rstrip(b"\0").decode(errors="replace")
    cmdline = d[64:64 + 512].split(b"\0")[0].decode(errors="replace")
    print(f"header: v{hv} pagesize={ps} kernel={ks}@0x{ka:08x} "
          f"ramdisk={rs}@0x{ra:08x} tags=0x{ta:08x}")
    print(f"name={name!r}")
    print(f"cmdline={cmdline!r}")
    if cmdline.startswith("'") or cmdline.endswith("'"):
        print("ERROR: command line contains stray quotes")
        return 1

    kern = d[ps:ps + ks]
    try:
        z = zlib.decompressobj(16 + zlib.MAX_WBITS)
        image = z.decompress(kern)
        consumed = len(kern) - len(z.unused_data)
    except zlib.error as e:
        print(f"ERROR: kernel is not a valid gzip stream: {e}")
        return 1
    dtb = kern[consumed:]
    print(f"kernel: gzip member {consumed} bytes -> Image {len(image)} bytes")
    if dtb[:4] != b"\xd0\x0d\xfe\xed":
        print(f"ERROR: no appended DTB (got {dtb[:4].hex()})")
        return 1
    dtb_total = int.from_bytes(dtb[4:8], "big")
    print(f"dtb: {len(dtb)} bytes, totalsize={dtb_total}")

    if len(image) < 0x40:
        print("ERROR: Image too short")
        return 1
    code0, code1 = struct.unpack_from("<II", image, 0)
    text_off, image_size, flags = struct.unpack_from("<QQQ", image, 8)
    magic = image[0x38:0x3c]
    print(f"Image: code0=0x{code0:08x} code1=0x{code1:08x} "
          f"text_offset=0x{text_off:x} image_size=0x{image_size:x} "
          f"flags=0x{flags:x} magic={magic!r}")
    if magic != b"ARMd":
        print("ERROR: missing arm64 Image magic")
        return 1
    # code0 must be a NOP (0xd503201f) or the EFI "MZ" ccmp for a
    # non-EFI bootloader to execute it safely.
    if code0 == 0xd503201f:
        print("Image entry: NOP/branch (non-EFI, hboot-safe)")
    elif code0 == 0xfa405a4d:
        print("Image entry: EFI-stub 'MZ' ccmp (still executable, but "
              "CONFIG_EFI_ZBOOT must be off)")
    else:
        print(f"WARNING: unexpected code0 0x{code0:08x}")

    # Ramdisk is loaded by hboot at ra; the kernel decompresses to ka.
    if ka < ra + rs and ra < ka + image_size:
        print(f"WARNING: ramdisk [0x{ra:08x}, 0x{ra + rs:08x}) overlaps "
              f"the kernel image [0x{ka:08x}, 0x{ka + image_size:08x})")
    else:
        print("layout: kernel and ramdisk do not overlap")

    rd = d[ps + ((ks + ps - 1) // ps) * ps:][:rs]
    if rd[:2] == b"\x1f\x8b":
        try:
            raw = gzip.GzipFile(fileobj=io.BytesIO(rd)).read()
        except Exception as e:  # noqa: BLE001
            print(f"WARNING: ramdisk gzip error: {e}")
            raw = b""
        print(f"ramdisk: gzip -> {len(raw)} bytes")
    else:
        raw = rd
        print(f"ramdisk: uncompressed {len(raw)} bytes")
    if raw[:6] in (b"070701", b"070702"):
        entries = raw.count(b"07070")
        print(f"ramdisk: newc cpio with ~{entries} entries")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
