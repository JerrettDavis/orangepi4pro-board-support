#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
device=/dev/mmcblk1
package=
backup_dir=/var/cache/orangepi4pro-images/bootloader-backups
dry_run=true
force=false
seek_blocks=2050
block_size=8192

usage() {
  cat <<'USAGE'
Install an Allwinner TOC1 boot package into the SD-card bootloader slot.

Usage:
  scripts/install-sd-boot-package.sh --package PACKAGE [--device /dev/mmcblk1] [--backup-dir DIR] [--yes]

Defaults to dry-run mode. In write mode, the script:
  - validates PACKAGE with scripts/sunxi-toc1-package.py;
  - refuses non-block devices;
  - refuses devices whose first partition starts too close to the boot package;
  - backs up the existing bootloader range before writing;
  - writes only PACKAGE to bs=8192 seek=2050 with conv=fsync,notrunc.

It does not write boot0, NVMe, SPI/MTD, partitions, filesystems, or firmware.
Set ORANGEPI4PRO_ALLOW_BOOTLOADER_WRITE=1 and pass --yes to write.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --package)
      package=${2:-}
      shift
      ;;
    --device)
      device=${2:-}
      shift
      ;;
    --backup-dir)
      backup_dir=${2:-}
      shift
      ;;
    --yes)
      dry_run=false
      ;;
    --force)
      force=true
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

if [ -z "$package" ]; then
  printf 'ERROR: --package is required\n' >&2
  usage >&2
  exit 2
fi

if [ ! -f "$package" ]; then
  printf 'ERROR: package not found: %s\n' "$package" >&2
  exit 1
fi

if [ ! -b "$device" ]; then
  printf 'ERROR: not a block device: %s\n' "$device" >&2
  exit 1
fi

package_size=$(stat -c '%s' "$package")
if [ "$package_size" -le 0 ]; then
  printf 'ERROR: package is empty: %s\n' "$package" >&2
  exit 1
fi

package_sha=$(sha256sum "$package" | awk '{print $1}')
case "$package_sha" in
  34f52a23883a427d6471bdfc69654ef853a6f96a1f406a732acd64a35555852f)
    if [ "${ORANGEPI4PRO_ALLOW_UNSAFE_BOOTLOADER_WRITE:-}" != 1 ]; then
      printf 'ERROR: refusing known-unsafe boot package: %s\n' "$package_sha" >&2
      printf '  package=%s\n' "$package" >&2
      printf '  reason=2026-07-03 DRM full-display reinit package did not boot and required external recovery\n' >&2
      printf 'Set ORANGEPI4PRO_ALLOW_UNSAFE_BOOTLOADER_WRITE=1 only for deliberate bench recovery testing.\n' >&2
      exit 1
    fi
    ;;
  dac4949d4e5ad3fdb8c3db0bf16811f2ce8ed4948c242ffeebe3c052d940f7a1)
    if [ "${ORANGEPI4PRO_ALLOW_UNSAFE_BOOTLOADER_WRITE:-}" != 1 ]; then
      printf 'ERROR: refusing known-unsafe boot package: %s\n' "$package_sha" >&2
      printf '  package=%s\n' "$package" >&2
      printf '  reason=2026-07-04 forced post-logo HDMI reinit package did not boot normally and required external recovery\n' >&2
      printf 'Set ORANGEPI4PRO_ALLOW_UNSAFE_BOOTLOADER_WRITE=1 only for deliberate bench recovery testing.\n' >&2
      exit 1
    fi
    ;;
  feacc7a99a48a1f6a64318b8372042f0b24df36bc5bae1f35f4bcc36581e6438)
    if [ "${ORANGEPI4PRO_ALLOW_UNSAFE_BOOTLOADER_WRITE:-}" != 1 ]; then
      printf 'ERROR: refusing known-unsafe boot package: %s\n' "$package_sha" >&2
      printf '  package=%s\n' "$package" >&2
      printf '  reason=2026-07-04 RX-sense stale HDMI retry package did not boot normally and required external recovery\n' >&2
      printf 'Set ORANGEPI4PRO_ALLOW_UNSAFE_BOOTLOADER_WRITE=1 only for deliberate bench recovery testing.\n' >&2
      exit 1
    fi
    ;;
esac

if [ $((package_size % 4)) -ne 0 ]; then
  printf 'ERROR: package size is not 4-byte aligned: %s\n' "$package_size" >&2
  exit 1
fi

"$repo_root/scripts/sunxi-toc1-package.py" inspect "$package" >/dev/null

write_offset=$((seek_blocks * block_size))
write_end=$((write_offset + package_size))
first_partition_start_bytes=

if command -v partx >/dev/null 2>&1; then
  first_partition_start_sectors=$(partx -g -o START "$device" 2>/dev/null | awk 'NF { print $1; exit }')
  if [ -n "$first_partition_start_sectors" ]; then
    first_partition_start_bytes=$((first_partition_start_sectors * 512))
  fi
fi

if [ -z "$first_partition_start_bytes" ]; then
  printf 'ERROR: could not determine first partition start for %s\n' "$device" >&2
  exit 1
fi

if [ "$write_end" -ge "$first_partition_start_bytes" ] && [ "$force" != true ]; then
  printf 'ERROR: package write would overlap first partition\n' >&2
  printf '  write_end=%s first_partition_start=%s\n' "$write_end" "$first_partition_start_bytes" >&2
  exit 1
fi

backup_blocks=$(((write_end + block_size - 1) / block_size))
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_path="$backup_dir/$(basename "$device")-bootloader-before-${timestamp}.bin"

printf 'device=%s\n' "$device"
printf 'package=%s\n' "$package"
printf 'package_sha256=%s\n' "$package_sha"
printf 'package_size=%s\n' "$package_size"
printf 'write_offset=%s\n' "$write_offset"
printf 'write_end=%s\n' "$write_end"
printf 'first_partition_start=%s\n' "$first_partition_start_bytes"
printf 'backup_path=%s\n' "$backup_path"

if [ "$dry_run" = true ]; then
  printf 'dry_run=true\n'
  printf 'No write performed. Pass --yes and set ORANGEPI4PRO_ALLOW_BOOTLOADER_WRITE=1 to install.\n'
  exit 0
fi

if [ "${ORANGEPI4PRO_ALLOW_BOOTLOADER_WRITE:-}" != 1 ]; then
  printf 'ERROR: refusing write without ORANGEPI4PRO_ALLOW_BOOTLOADER_WRITE=1\n' >&2
  exit 1
fi

mkdir -p "$backup_dir"
sudo dd if="$device" of="$backup_path" bs="$block_size" count="$backup_blocks" status=none
sha256sum "$backup_path"

sudo dd if="$package" of="$device" bs="$block_size" seek="$seek_blocks" conv=fsync,notrunc status=none
sync

verify_path=$(mktemp)
trap 'rm -f "$verify_path"' EXIT
verify_blocks=$(((package_size + block_size - 1) / block_size))
sudo dd if="$device" of="$verify_path" bs="$block_size" skip="$seek_blocks" count="$verify_blocks" status=none
cmp -n "$package_size" "$package" "$verify_path"
printf 'Installed and verified SD boot package.\n'
