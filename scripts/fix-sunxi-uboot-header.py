#!/usr/bin/env python3
"""Fix Allwinner U-Boot spare header metadata in a built binary.

The Orange Pi vendor build invokes scripts/sunxi_ubootools, but that binary is
x86-64-only in the public tree and cannot run on the ARM board.  This helper
performs the subset needed for boot-package artifacts: set length fields and
recompute the spare header checksum.
"""

from __future__ import annotations

import argparse
import pathlib
import struct


STAMP_VALUE = 0x5F0A6C39
CHECKSUM_OFFSET = 12
LENGTH_OFFSET = 20
UBOOT_LENGTH_OFFSET = 24


def read_u32(data: bytearray, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def write_u32(data: bytearray, offset: int, value: int) -> None:
    struct.pack_into("<I", data, offset, value & 0xFFFFFFFF)


def fix_header(path: pathlib.Path) -> tuple[int, int]:
    data = bytearray(path.read_bytes())
    if len(data) < 64:
        raise SystemExit(f"{path}: file is too small for a U-Boot spare header")
    if data[4:12].split(b"\0", 1)[0] != b"uboot":
        raise SystemExit(f"{path}: missing U-Boot spare header magic")

    original_len = len(data)
    if len(data) % 4:
        data.extend(b"\0" * (4 - (len(data) % 4)))

    fixed_len = len(data)
    write_u32(data, LENGTH_OFFSET, fixed_len)
    write_u32(data, UBOOT_LENGTH_OFFSET, fixed_len)
    write_u32(data, CHECKSUM_OFFSET, STAMP_VALUE)

    words = struct.unpack(f"<{fixed_len // 4}I", data)
    checksum = sum(words) & 0xFFFFFFFF
    write_u32(data, CHECKSUM_OFFSET, checksum)
    path.write_bytes(data)
    return original_len, fixed_len


def verify_header(path: pathlib.Path) -> None:
    data = bytearray(path.read_bytes())
    if len(data) % 4:
        raise SystemExit(f"{path}: length is not 4-byte aligned")
    length = read_u32(data, LENGTH_OFFSET)
    uboot_length = read_u32(data, UBOOT_LENGTH_OFFSET)
    stored = read_u32(data, CHECKSUM_OFFSET)
    if length != len(data) or uboot_length != len(data):
        raise SystemExit(
            f"{path}: bad length fields length={length} "
            f"uboot_length={uboot_length} actual={len(data)}"
        )
    write_u32(data, CHECKSUM_OFFSET, STAMP_VALUE)
    calculated = sum(struct.unpack(f"<{len(data) // 4}I", data)) & 0xFFFFFFFF
    if stored != calculated:
        raise SystemExit(
            f"{path}: checksum mismatch stored=0x{stored:08x} "
            f"calculated=0x{calculated:08x}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=pathlib.Path)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()

    if args.verify:
        verify_header(args.path)
        print(f"{args.path}: header valid")
    else:
        original_len, fixed_len = fix_header(args.path)
        verify_header(args.path)
        print(
            f"{args.path}: fixed U-Boot header "
            f"original_len={original_len} fixed_len={fixed_len}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
