#!/usr/bin/env python3
"""Carve the squashfs payload out of a type-2 AppImage.

A type-2 AppImage is an ELF runtime with a squashfs image appended after the
ELF section header table. The runtime itself cannot be executed inside a Nix
build (no /lib64 loader), so we locate the payload by arithmetic instead:

    offset = e_shoff + e_shnum * e_shentsize

Usage: unpack-appimage.py <appimage> <output.squashfs>
"""

import struct
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    src, dst = sys.argv[1], sys.argv[2]

    with open(src, "rb") as f:
        header = f.read(64)
        if header[:4] != b"\x7fELF" or header[4] != 2:
            print(f"{src}: not a 64-bit ELF", file=sys.stderr)
            return 1
        if header[8:10] != b"AI":
            print(f"{src}: not an AppImage (missing 'AI' magic)", file=sys.stderr)
            return 1

        shoff = struct.unpack_from("<Q", header, 0x28)[0]
        shentsize = struct.unpack_from("<H", header, 0x3A)[0]
        shnum = struct.unpack_from("<H", header, 0x3C)[0]
        offset = shoff + shentsize * shnum

        f.seek(offset)
        if f.read(4) != b"hsqs":
            print(
                f"{src}: no squashfs superblock at computed offset {offset}",
                file=sys.stderr,
            )
            return 1
        f.seek(offset)
        with open(dst, "wb") as out:
            while chunk := f.read(1 << 20):
                out.write(chunk)

    print(f"payload: {dst} (squashfs at byte {offset})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
