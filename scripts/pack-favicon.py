#!/usr/bin/env python3
"""Pack 16/32 PNG icons into a multi-size favicon.ico (PNG-compressed ICO)."""

from __future__ import annotations

import struct
import subprocess
import sys
import tempfile
from pathlib import Path


def png_from_master(master: Path, size: int, dest: Path) -> None:
    subprocess.run(
        [
            "sips",
            "-z",
            str(size),
            str(size),
            str(master),
            "--out",
            str(dest),
        ],
        check=True,
        capture_output=True,
    )


def write_ico(pngs: list[bytes], dest: Path) -> None:
    count = len(pngs)
    offset = 6 + 16 * count
    entries = bytearray()
    data = bytearray()
    for png in pngs:
        width, height = struct.unpack(">II", png[16:24])
        ico_w = 0 if width >= 256 else width
        ico_h = 0 if height >= 256 else height
        entries += struct.pack(
            "<BBBBHHII",
            ico_w,
            ico_h,
            0,  # color count
            0,  # reserved
            1,  # planes
            32,  # bit count
            len(png),
            offset + len(data),
        )
        data += png

    header = struct.pack("<HHH", 0, 1, count)
    dest.write_bytes(header + entries + data)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    web_app = root.parent / "web" / "app"
    # Prefer rounded web mark (transparent corners); fall back to Mac full-bleed.
    master = web_app / "icon.png"
    if not master.is_file():
        master = root / "Resources" / "AppIcon.png"
    if not master.is_file():
        print(f"missing master icon: {master}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        png_blobs: list[bytes] = []
        for size in (16, 32):
            out = tmp_path / f"icon-{size}.png"
            png_from_master(master, size, out)
            png_blobs.append(out.read_bytes())

        dest = web_app / "favicon.ico"
        write_ico(png_blobs, dest)
        print(f"Wrote {dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
