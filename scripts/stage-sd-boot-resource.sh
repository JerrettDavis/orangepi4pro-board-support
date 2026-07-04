#!/usr/bin/env bash
set -euo pipefail

device=/dev/mmcblk1
source_logo=/boot/logo.bmp
backup_dir=/var/cache/orangepi4pro-images/bootloader-backups
logical_offset=40960
mbr_copies=4
mbr_copy_sectors=32
resource_start_logical=128
resource_end_absolute=65536
dry_run=true

usage() {
  cat <<'USAGE'
Stage a minimal Allwinner SD boot-resource area for U-Boot logo loading.

Usage:
  scripts/stage-sd-boot-resource.sh [--device /dev/mmcblk1] [--source-logo FILE] [--yes]

Defaults to dry-run mode. In write mode, this script:
  - backs up the reserved SD range it will modify;
  - writes four 16 KiB Allwinner softw411 MBR copies at absolute sector 40960;
  - writes a FAT16 boot-resource filesystem starting at absolute sector 41088;
  - copies bootlogo.bmp, boot.bmp, and boot1.bmp into that filesystem;
  - verifies the written MBR magic, FAT label, and logo files by readback.

It never writes boot0, TOC1/U-Boot, SPI/MTD, NVMe, partition tables, or the
Linux root filesystem. Set ORANGEPI4PRO_ALLOW_BOOT_RESOURCE_WRITE=1 and pass
--yes to write.
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
    --backup-dir)
      backup_dir=${2:-}
      shift
      ;;
    --yes)
      dry_run=false
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
command -v mkfs.vfat >/dev/null 2>&1 || fail 'mkfs.vfat is required'
command -v losetup >/dev/null 2>&1 || fail 'losetup is required'

first_partition_start=$(partx -g -o START "$device" 2>/dev/null | awk 'NF { print $1; exit }')
[ -n "$first_partition_start" ] || fail "could not determine first partition start for $device"
[ "$first_partition_start" -eq "$resource_end_absolute" ] \
  || fail "unexpected first partition start: $first_partition_start"

mbr_start_absolute=$logical_offset
mbr_total_sectors=$((mbr_copies * mbr_copy_sectors))
resource_start_absolute=$((logical_offset + resource_start_logical))
resource_sectors=$((resource_end_absolute - resource_start_absolute))
resource_bytes=$((resource_sectors * 512))
write_start=$mbr_start_absolute
write_sectors=$((resource_end_absolute - write_start))

[ "$resource_start_absolute" -gt "$((logical_offset + mbr_total_sectors - 1))" ] \
  || fail 'resource filesystem would overlap Allwinner MBR copies'
[ "$resource_end_absolute" -le "$first_partition_start" ] \
  || fail 'resource filesystem would overlap the first Linux partition'

tmpdir=$(mktemp -d)
loopdev=
mount_dir=
cleanup() {
  if [ -n "$mount_dir" ] && mountpoint -q "$mount_dir"; then
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

python3 - "$mbr_path" "$resource_start_logical" "$resource_sectors" "$mbr_copies" <<'PY'
from pathlib import Path
import struct
import sys
import zlib

out = Path(sys.argv[1])
start = int(sys.argv[2])
length = int(sys.argv[3])
copies = int(sys.argv[4])
sector = 512
mbr_size = 16 * 1024
partition_size = 128
part_count = 1
reserved_len = mbr_size - 32 - 4 - (120 * partition_size)

def cstr(value, size):
    data = value.encode("ascii")
    if len(data) >= size:
        raise SystemExit(f"{value} is too long")
    return data + b"\0" * (size - len(data))

def fixed(value, size):
    data = value.encode("ascii")
    if len(data) != size:
        raise SystemExit(f"{value} must be exactly {size} bytes")
    return data

partition = struct.pack(
    "<4I16s16s5I4I2I36s",
    0,
    start,
    0,
    length,
    cstr("boot-resource", 16),
    cstr("boot-resource", 16),
    0x8000,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    b"\0" * 36,
)
assert len(partition) == partition_size
partitions = partition + b"\0" * (partition_size * 119)

blob = bytearray()
for index in range(copies):
    body = bytearray()
    body += struct.pack("<I", 0x100)
    body += fixed("softw411", 8)
    body += struct.pack("<4I", copies, index, part_count, 0)
    body += partitions
    body += struct.pack("<I", 0xA5)
    body += b"\0" * reserved_len
    crc = zlib.crc32(body) & 0xFFFFFFFF
    copy = struct.pack("<I", crc) + body
    if len(copy) != mbr_size:
        raise SystemExit(f"bad MBR size: {len(copy)}")
    blob += copy

out.write_bytes(blob)
print(f"mbr_sha256_pending={out}")
PY

truncate -s "$resource_bytes" "$fat_path"
mkfs.vfat --invariant -F 16 -n BOOTRES "$fat_path" >/dev/null
mount_dir="$tmpdir/mnt"
mkdir -p "$mount_dir"
loopdev=$(losetup --find --show "$fat_path")
mount "$loopdev" "$mount_dir"
install -m 0644 "$source_logo" "$mount_dir/bootlogo.bmp"
install -m 0644 "$source_logo" "$mount_dir/boot.bmp"
install -m 0644 "$source_logo" "$mount_dir/boot1.bmp"
sync
umount "$mount_dir"
losetup -d "$loopdev"
loopdev=

printf 'device=%s\n' "$device"
printf 'source_logo=%s\n' "$source_logo"
printf 'logical_offset_sectors=%s\n' "$logical_offset"
printf 'mbr_start_absolute_sector=%s\n' "$mbr_start_absolute"
printf 'mbr_copies=%s\n' "$mbr_copies"
printf 'mbr_total_sectors=%s\n' "$mbr_total_sectors"
printf 'resource_start_absolute_sector=%s\n' "$resource_start_absolute"
printf 'resource_sectors=%s\n' "$resource_sectors"
printf 'resource_end_absolute_sector=%s\n' "$resource_end_absolute"
printf 'first_partition_start_sector=%s\n' "$first_partition_start"
sha256sum "$mbr_path" "$fat_path" "$source_logo"

if [ "$dry_run" = true ]; then
  printf 'dry_run=true\n'
  printf 'No write performed. Pass --yes and set ORANGEPI4PRO_ALLOW_BOOT_RESOURCE_WRITE=1 to install.\n'
  exit 0
fi

[ "${ORANGEPI4PRO_ALLOW_BOOT_RESOURCE_WRITE:-}" = 1 ] \
  || fail 'refusing write without ORANGEPI4PRO_ALLOW_BOOT_RESOURCE_WRITE=1'

mkdir -p "$backup_dir"
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_path="$backup_dir/$(basename "$device")-boot-resource-before-${timestamp}.bin"
dd if="$device" of="$backup_path" bs=512 skip="$write_start" count="$write_sectors" status=none
sha256sum "$backup_path"

dd if="$mbr_path" of="$device" bs=512 seek="$mbr_start_absolute" conv=fsync,notrunc status=none
dd if="$fat_path" of="$device" bs=512 seek="$resource_start_absolute" conv=fsync,notrunc status=none
sync

verify_mbr="$tmpdir/verify-mbr.bin"
verify_fat="$tmpdir/verify-fat.bin"
dd if="$device" of="$verify_mbr" bs=512 skip="$mbr_start_absolute" count="$mbr_total_sectors" status=none
dd if="$device" of="$verify_fat" bs=512 skip="$resource_start_absolute" count="$resource_sectors" status=none
cmp "$mbr_path" "$verify_mbr"
cmp "$fat_path" "$verify_fat"

loopdev=$(losetup --find --show "$verify_fat")
mount "$loopdev" "$mount_dir"
for file in bootlogo.bmp boot.bmp boot1.bmp; do
  cmp "$source_logo" "$mount_dir/$file"
done
umount "$mount_dir"
losetup -d "$loopdev"
loopdev=

printf 'Installed and verified SD boot-resource area.\n'
