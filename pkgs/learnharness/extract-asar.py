#!/usr/bin/env python3
"""Extract an asar archive into a plain directory tree.

Layout (little-endian)::

    u32 = 4                      # size of the next field
    u32 = header_pickle_size
    u32 = 4                      # size of the next field
    u32 = json_size
    json header
    ... file contents, offsets relative to 8 + header_pickle_size

The shell is unpacked rather than kept as app.asar so that electron/main.cjs
can be patched (Electron prefers resources/app.asar over resources/app, so the
archive must be removed for the directory to be used).

Usage: extract-asar.py <app.asar> <outdir>
"""

import json
import os
import struct
import sys


def extract(archive: str, outdir: str) -> int:
    with open(archive, "rb") as f:
        head = f.read(8)
        if len(head) != 8:
            print(f"{archive}: truncated header", file=sys.stderr)
            return 1
        pickle_size = struct.unpack("<I", head[4:8])[0]
        pickle = f.read(pickle_size)
        json_size = struct.unpack("<I", pickle[4:8])[0]
        header = json.loads(pickle[8 : 8 + json_size])
        base = 8 + pickle_size

        def walk(node: dict, path: str) -> None:
            for name, meta in node.get("files", {}).items():
                target = os.path.join(path, name)
                if "files" in meta:
                    os.makedirs(target, exist_ok=True)
                    walk(meta, target)
                    continue
                if meta.get("unpacked"):
                    print(
                        f"{archive}: unpacked entry {target} is not supported",
                        file=sys.stderr,
                    )
                    raise SystemExit(1)
                os.makedirs(os.path.dirname(target), exist_ok=True)
                f.seek(base + int(meta.get("offset", 0)))
                with open(target, "wb") as out:
                    out.write(f.read(int(meta.get("size", 0))))
                mode = meta.get("executable")
                if mode:
                    os.chmod(target, 0o755)

        os.makedirs(outdir, exist_ok=True)
        walk(header, outdir)
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(extract(sys.argv[1], sys.argv[2]))
