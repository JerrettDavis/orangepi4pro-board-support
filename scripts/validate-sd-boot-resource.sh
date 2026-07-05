#!/usr/bin/env bash
set -euo pipefail

device=/dev/mmcblk1
source_logo=/boot/logo.bmp
logical_offset=40960
mbr_copies=4
mbr_copy_sectors=32
resource_start_logical=128
resource_end_absolute=65536

usage() {
  cat <<'USAGE'
Validate the Allwinner SD boot-resource area used by vendor U-Boot logos.

Usage:
  scripts/validate-sd-boot-resource.sh [--device /dev/mmcblk1] [--source-logo FILE]

This is read-only. It checks the softw411 MBR copies at sector 40960, mounts
the boot-resource FAT image read-only, and verifies bootlogo.bmp, boot.bmp,
boot1.bmp, and fastbootlogo.bmp against the expected source logo.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device)
      device=${2:-}
      shift
      ;;
    --source-logo)
      source_logo=${2:-}
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[ -b "$device" ] || fail "not a block device: $device"
[ -r "$source_logo" ] || fail "source logo is not readable: $source_logo"
command -v losetup >/dev/null 2>&1 || fail 'losetup is required'

first_partition_start=$(partx -g -o START "$device" 2>/dev/null | awk 'NF { print $1; exit }')
[ -n "$first_partition_start" ] || fail "could not determine first partition start for $device"
[ "$first_partition_start" -eq "$resource_end_absolute" ] \
  || fail "unexpected first partition start: $first_partition_start"

mbr_start_absolute=$logical_offset
mbr_total_sectors=$((mbr_copies * mbr_copy_sectors))
resource_start_absolute=$((logical_offset + resource_start_logical))
resource_sectors=$((resource_end_absolute - resource_start_absolute))

tmpdir=$(mktemp -d)
loopdev=
mount_dir="$tmpdir/mnt"
cleanup() {
  if mountpoint -q "$mount_dir" 2>/dev/null; then
    umount "$mount_dir" || true
  fi
  if [ -n "$loopdev" ]; then
    losetup -d "$loopdev" || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

mbr_path="$tmpdir/sunxi-mbr.bin"
fat_path="$tmpdir/boot-resource.fat"
dd if="$device" of="$mbr_path" bs=512 skip="$mbr_start_absolute" count="$mbr_total_sectors" status=none
dd if="$device" of="$fat_path" bs=512 skip="$resource_start_absolute" count="$resource_sectors" status=none

python3 - "$mbr_path" "$resource_start_logical" "$resource_sectors" "$mbr_copies" <<'PY'
from pathlib import Path
import struct
import sys
import zlib

path = Path(sys.argv[1])
expected_start = int(sys.argv[2])
expected_len = int(sys.argv[3])
expected_copies = int(sys.argv[4])
data = path.read_bytes()
copy_size = 16 * 1024
part_size = 128

if len(data) != expected_copies * copy_size:
    raise SystemExit(f"bad MBR readback length: {len(data)}")

for index in range(expected_copies):
    chunk = data[index * copy_size : (index + 1) * copy_size]
    stored_crc, = struct.unpack_from("<I", chunk, 0)
    calculated_crc = zlib.crc32(chunk[4:]) & 0xFFFFFFFF
    if stored_crc != calculated_crc:
        raise SystemExit(
            f"MBR copy {index} CRC mismatch: "
            f"stored=0x{stored_crc:08x} calculated=0x{calculated_crc:08x}"
        )
    if chunk[8:16] != b"softw411":
        raise SystemExit(f"MBR copy {index} missing softw411 magic")
    copies, copy_index, part_count, _ = struct.unpack_from("<4I", chunk, 16)
    if copies != expected_copies or copy_index != index or part_count != 1:
        raise SystemExit(
            f"MBR copy {index} bad header copies={copies} "
            f"copy_index={copy_index} part_count={part_count}"
        )
    part = chunk[32 : 32 + part_size]
    fields = struct.unpack("<4I16s16s5I4I2I36s", part)
    start = fields[1]
    length = fields[3]
    name = fields[4].split(b"\0", 1)[0]
    klass = fields[5].split(b"\0", 1)[0]
    user_type = fields[6]
    if start != expected_start or length != expected_len:
        raise SystemExit(
            f"MBR copy {index} bad boot-resource range: "
            f"start={start} length={length}"
        )
    if name != b"boot-resource" or klass != b"boot-resource" or user_type != 0x8000:
        raise SystemExit(
            f"MBR copy {index} bad boot-resource identity: "
            f"name={name!r} class={klass!r} user_type=0x{user_type:x}"
        )

print("softw411 boot-resource MBR validation passed")
PY

mkdir -p "$mount_dir"
loopdev=$(losetup --find --show "$fat_path")
mount -o ro "$loopdev" "$mount_dir"
for file in bootlogo.bmp boot.bmp boot1.bmp fastbootlogo.bmp; do
  cmp "$source_logo" "$mount_dir/$file"
done

printf 'SD boot-resource validation passed.\n'
sha256sum "$mbr_path" "$fat_path" "$source_logo"
