#!/usr/bin/env bash
set -euo pipefail

device=/dev/mmcblk1
backup=
write_start=40960
dry_run=true

usage() {
  cat <<'USAGE'
Restore the reserved SD boot-resource window from a previous backup.

Usage:
  scripts/restore-sd-boot-resource-backup.sh --backup FILE [--device /dev/mmcblk1] [--yes]

The restore window starts at absolute sector 40960 and spans exactly the backup
file length. This is intended to undo scripts/stage-sd-boot-resource.sh by
restoring the pre-write reserved area backup. It refuses to overlap the first
Linux partition and defaults to dry-run mode.

Set ORANGEPI4PRO_ALLOW_BOOT_RESOURCE_RESTORE=1 and pass --yes to write.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --backup)
      backup=${2:-}
      shift
      ;;
    --device)
      device=${2:-}
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

[ -n "$backup" ] || fail '--backup is required'
[ -f "$backup" ] || fail "backup not found: $backup"
[ -b "$device" ] || fail "not a block device: $device"

backup_size=$(stat -c '%s' "$backup")
[ "$backup_size" -gt 0 ] || fail "backup is empty: $backup"
[ $((backup_size % 512)) -eq 0 ] || fail "backup size is not sector aligned: $backup_size"

first_partition_start=$(partx -g -o START "$device" 2>/dev/null | awk 'NF { print $1; exit }')
[ -n "$first_partition_start" ] || fail "could not determine first partition start for $device"

write_sectors=$((backup_size / 512))
write_end=$((write_start + write_sectors))
[ "$write_end" -le "$first_partition_start" ] \
  || fail "restore window would overlap first partition: end=$write_end first=$first_partition_start"

printf 'device=%s\n' "$device"
printf 'backup=%s\n' "$backup"
printf 'backup_sha256=%s\n' "$(sha256sum "$backup" | awk '{print $1}')"
printf 'write_start_sector=%s\n' "$write_start"
printf 'write_sectors=%s\n' "$write_sectors"
printf 'write_end_sector=%s\n' "$write_end"
printf 'first_partition_start_sector=%s\n' "$first_partition_start"

if [ "$dry_run" = true ]; then
  printf 'dry_run=true\n'
  printf 'No write performed. Pass --yes and set ORANGEPI4PRO_ALLOW_BOOT_RESOURCE_RESTORE=1 to restore.\n'
  exit 0
fi

[ "${ORANGEPI4PRO_ALLOW_BOOT_RESOURCE_RESTORE:-}" = 1 ] \
  || fail 'refusing write without ORANGEPI4PRO_ALLOW_BOOT_RESOURCE_RESTORE=1'

dd if="$backup" of="$device" bs=512 seek="$write_start" conv=fsync,notrunc status=none
sync

verify_path=$(mktemp)
trap 'rm -f "$verify_path"' EXIT
dd if="$device" of="$verify_path" bs=512 skip="$write_start" count="$write_sectors" status=none
cmp "$backup" "$verify_path"
printf 'Restored and verified reserved SD boot-resource window.\n'
