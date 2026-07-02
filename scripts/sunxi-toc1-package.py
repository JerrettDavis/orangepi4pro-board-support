#!/usr/bin/env python3
"""Inspect and rebuild Allwinner sunxi TOC1 boot packages.

This tool is intentionally file-only. It never writes block devices, MTD
devices, or installed bootloader locations.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import pathlib
import struct
import sys
import tempfile


STAMP_VALUE = 0x5F0A6C39
TOC1_MAGIC = 0x89119800
HEADER_SIZE = 0x40
ITEM_SIZE = 0x170
DEFAULT_ALIGN = 0x400


@dataclasses.dataclass
class Toc1Item:
    name: str
    data_offset: int
    data_len: int
    encrypt: int
    item_type: int
    run_addr: int
    index: int
    reserved: tuple[int, ...]
    end: int


@dataclasses.dataclass
class Toc1Package:
    path: pathlib.Path | None
    data: bytes
    words: tuple[int, ...]
    name: str
    magic: int
    checksum: int
    serial_num: int
    status: int
    items_nr: int
    valid_len: int
    version_main: int
    version_sub: int
    reserved: tuple[int, int, int]
    end: int
    items: list[Toc1Item]


def align_up(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def decode_c_string(raw: bytes) -> str:
    return raw.split(b"\0", 1)[0].decode("ascii", errors="replace")


def encode_c_string(value: str, size: int) -> bytes:
    encoded = value.encode("ascii")
    if len(encoded) >= size:
        raise ValueError(f"{value!r} does not fit in {size} byte field")
    return encoded + b"\0" * (size - len(encoded))


def checksum_words(data: bytes) -> tuple[int, int]:
    if len(data) % 4 != 0:
        raise ValueError("TOC1 package length must be 4-byte aligned")
    words = list(struct.unpack(f"<{len(data) // 4}I", data))
    if len(words) < 6:
        raise ValueError("TOC1 package is too small")
    stored = words[5]
    words[5] = 0
    calculated = (sum(words) + STAMP_VALUE) & 0xFFFFFFFF
    return stored, calculated


def parse_package(path: pathlib.Path | None, data: bytes) -> Toc1Package:
    if len(data) < HEADER_SIZE:
        raise ValueError("TOC1 package is smaller than the header")
    if len(data) % 4 != 0:
        raise ValueError("TOC1 package length must be 4-byte aligned")

    header = struct.unpack("<16s12I", data[:HEADER_SIZE])
    name = decode_c_string(header[0])
    magic = header[1]
    if magic != TOC1_MAGIC:
        raise ValueError(f"unexpected TOC1 magic 0x{magic:08x}")

    items_nr = header[5]
    item_table_len = HEADER_SIZE + items_nr * ITEM_SIZE
    if item_table_len > len(data):
        raise ValueError("TOC1 item table extends past package length")

    items: list[Toc1Item] = []
    for index in range(items_nr):
        start = HEADER_SIZE + index * ITEM_SIZE
        raw = data[start : start + ITEM_SIZE]
        unpacked = struct.unpack("<64s6I69II", raw)
        item = Toc1Item(
            name=decode_c_string(unpacked[0]),
            data_offset=unpacked[1],
            data_len=unpacked[2],
            encrypt=unpacked[3],
            item_type=unpacked[4],
            run_addr=unpacked[5],
            index=unpacked[6],
            reserved=tuple(unpacked[7:76]),
            end=unpacked[76],
        )
        if item.data_offset + item.data_len > len(data):
            raise ValueError(f"item {item.name!r} extends past package length")
        items.append(item)

    return Toc1Package(
        path=path,
        data=data,
        words=tuple(struct.unpack(f"<{len(data) // 4}I", data)),
        name=name,
        magic=magic,
        checksum=header[2],
        serial_num=header[3],
        status=header[4],
        items_nr=items_nr,
        valid_len=header[6],
        version_main=header[7],
        version_sub=header[8],
        reserved=(header[9], header[10], header[11]),
        end=header[12],
        items=items,
    )


def read_package(path: pathlib.Path) -> Toc1Package:
    return parse_package(path, path.read_bytes())


def package_summary(package: Toc1Package) -> dict[str, object]:
    stored, calculated = checksum_words(package.data)
    return {
        "path": str(package.path) if package.path else None,
        "name": package.name,
        "magic": f"0x{package.magic:08x}",
        "checksum": f"0x{package.checksum:08x}",
        "checksum_valid": stored == calculated,
        "checksum_calculated": f"0x{calculated:08x}",
        "items_nr": package.items_nr,
        "valid_len": package.valid_len,
        "length": len(package.data),
        "sha256": hashlib.sha256(package.data).hexdigest(),
        "items": [
            {
                "name": item.name,
                "offset": item.data_offset,
                "length": item.data_len,
                "sha256": hashlib.sha256(
                    package.data[item.data_offset : item.data_offset + item.data_len]
                ).hexdigest(),
                "encrypt": item.encrypt,
                "type": item.item_type,
                "run_addr": f"0x{item.run_addr:08x}",
                "index": item.index,
            }
            for item in package.items
        ],
    }


def parse_replacements(values: list[str]) -> dict[str, pathlib.Path]:
    replacements: dict[str, pathlib.Path] = {}
    for value in values:
        if "=" not in value:
            raise ValueError(f"replacement must be name=path: {value}")
        name, path = value.split("=", 1)
        if not name:
            raise ValueError("replacement item name cannot be empty")
        replacements[name] = pathlib.Path(path)
    return replacements


def build_package(
    template: Toc1Package,
    replacements: dict[str, pathlib.Path],
    alignment: int = DEFAULT_ALIGN,
) -> bytes:
    missing = sorted(set(replacements) - {item.name for item in template.items})
    if missing:
        raise ValueError(f"template does not contain replacement item(s): {', '.join(missing)}")

    payloads: dict[str, bytes] = {}
    for item in template.items:
        if item.name in replacements:
            payloads[item.name] = replacements[item.name].read_bytes()
        else:
            payloads[item.name] = template.data[item.data_offset : item.data_offset + item.data_len]

    payload_offset = align_up(HEADER_SIZE + len(template.items) * ITEM_SIZE, alignment)
    item_records: list[tuple[Toc1Item, int, bytes]] = []
    cursor = payload_offset
    for item in template.items:
        cursor = align_up(cursor, alignment)
        payload = payloads[item.name]
        item_records.append((item, cursor, payload))
        cursor += len(payload)

    total_len = max(template.valid_len, align_up(cursor, alignment))
    output = bytearray(template.data)
    if len(output) < total_len:
        output.extend(b"\0" * (total_len - len(output)))
    else:
        del output[total_len:]
    header = struct.pack(
        "<16s12I",
        encode_c_string(template.name, 16),
        template.magic,
        0,
        template.serial_num,
        template.status,
        template.items_nr,
        total_len,
        template.version_main,
        template.version_sub,
        *template.reserved,
        template.end,
    )
    output[:HEADER_SIZE] = header

    for index, (item, offset, payload) in enumerate(item_records):
        item_raw = struct.pack(
            "<64s6I69II",
            encode_c_string(item.name, 64),
            offset,
            len(payload),
            item.encrypt,
            item.item_type,
            item.run_addr,
            item.index,
            *item.reserved,
            item.end,
        )
        start = HEADER_SIZE + index * ITEM_SIZE
        output[start : start + ITEM_SIZE] = item_raw
        output[offset : offset + len(payload)] = payload

    words = list(struct.unpack(f"<{len(output) // 4}I", output))
    words[5] = (sum(words) + STAMP_VALUE) & 0xFFFFFFFF
    return struct.pack(f"<{len(words)}I", *words)


def command_inspect(args: argparse.Namespace) -> int:
    for path in args.package:
        summary = package_summary(read_package(path))
        if args.json:
            print(json.dumps(summary, indent=2, sort_keys=True))
            continue
        print(f"{path}")
        print(f"  name: {summary['name']}")
        print(f"  magic: {summary['magic']}")
        print(
            f"  checksum: {summary['checksum']} "
            f"(valid={str(summary['checksum_valid']).lower()})"
        )
        print(f"  length: {summary['length']}")
        print(f"  sha256: {summary['sha256']}")
        for item in summary["items"]:
            print(
                "  item {name}: offset=0x{offset:x} length=0x{length:x} sha256={sha256}".format(
                    **item
                )
            )
    return 0


def command_repack(args: argparse.Namespace) -> int:
    template = read_package(args.template)
    replacements = parse_replacements(args.replace)
    output = build_package(template, replacements, args.align)
    rebuilt = parse_package(args.output, output)
    stored, calculated = checksum_words(output)
    if stored != calculated:
        raise RuntimeError("internal error: rebuilt checksum is invalid")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(output)
    print(f"wrote {args.output}")
    print(f"length={len(output)} sha256={hashlib.sha256(output).hexdigest()}")
    for item in package_summary(rebuilt)["items"]:
        print(
            "item {name}: offset=0x{offset:x} length=0x{length:x} sha256={sha256}".format(
                **item
            )
        )
    return 0


def command_selftest(_args: argparse.Namespace) -> int:
    header = struct.pack(
        "<16s12I",
        encode_c_string("sunxi-package", 16),
        TOC1_MAGIC,
        0,
        0,
        0,
        2,
        0,
        0,
        0,
        0,
        0,
        0,
        0x3B45494D,
    )
    payload_a = b"A" * 17
    payload_b = b"B" * 19
    base = bytearray(DEFAULT_ALIGN * 3)
    base[:HEADER_SIZE] = header
    for idx, (name, offset, payload) in enumerate(
        (("u-boot", DEFAULT_ALIGN, payload_a), ("scp", DEFAULT_ALIGN * 2, payload_b))
    ):
        item = Toc1Item(name, offset, len(payload), 0, 3, 0, idx, (0,) * 69, 0x3B45494D)
        raw = struct.pack(
            "<64s6I69II",
            encode_c_string(item.name, 64),
            item.data_offset,
            item.data_len,
            item.encrypt,
            item.item_type,
            item.run_addr,
            item.index,
            *item.reserved,
            item.end,
        )
        start = HEADER_SIZE + idx * ITEM_SIZE
        base[start : start + ITEM_SIZE] = raw
        base[offset : offset + len(payload)] = payload
    words = list(struct.unpack(f"<{len(base) // 4}I", base))
    words[5] = (sum(words) + STAMP_VALUE) & 0xFFFFFFFF
    package = parse_package(None, struct.pack(f"<{len(words)}I", *words))
    with tempfile.TemporaryDirectory() as tmpdir:
        replacement = pathlib.Path(tmpdir) / "replacement.bin"
        replacement.write_bytes(b"new u-boot payload")
        rebuilt = build_package(package, {"u-boot": replacement})
    parsed = parse_package(None, rebuilt)
    stored, calculated = checksum_words(rebuilt)
    assert stored == calculated
    assert parsed.items[0].name == "u-boot"
    assert parsed.items[0].data_len == len(b"new u-boot payload")
    assert parsed.items[1].name == "scp"
    print("sunxi TOC1 package self-test passed")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(required=True)

    inspect_parser = subparsers.add_parser("inspect", help="inspect package metadata")
    inspect_parser.add_argument("package", nargs="+", type=pathlib.Path)
    inspect_parser.add_argument("--json", action="store_true", help="emit JSON")
    inspect_parser.set_defaults(func=command_inspect)

    repack_parser = subparsers.add_parser("repack", help="rebuild package from a template")
    repack_parser.add_argument("--template", required=True, type=pathlib.Path)
    repack_parser.add_argument("--output", required=True, type=pathlib.Path)
    repack_parser.add_argument(
        "--replace",
        action="append",
        default=[],
        metavar="NAME=PATH",
        help="replace a package item payload by item name",
    )
    repack_parser.add_argument("--align", type=int, default=DEFAULT_ALIGN)
    repack_parser.set_defaults(func=command_repack)

    selftest_parser = subparsers.add_parser("selftest", help="run synthetic format tests")
    selftest_parser.set_defaults(func=command_selftest)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
