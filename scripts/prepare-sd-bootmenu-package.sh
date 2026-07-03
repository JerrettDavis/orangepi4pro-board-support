#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
template=${TEMPLATE:-/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu.fex}
uboot=${UBOOT:-"$repo_root/.build/u-boot/artifacts/bootmenu/u-boot-sun60iw2p1.bin"}
output=${OUTPUT:-/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu-scriptfirst.fex}

usage() {
  cat <<'USAGE'
Prepare a file-only SD bootmenu package candidate.

Usage:
  scripts/prepare-sd-bootmenu-package.sh [--template FILE] [--uboot FILE] [--output FILE]

Defaults:
  TEMPLATE=/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu.fex
  UBOOT=.build/u-boot/artifacts/bootmenu/u-boot-sun60iw2p1.bin
  OUTPUT=/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu-scriptfirst.fex

This script only creates and validates a package file. It does not run dd,
write /dev/mmcblk*, write /dev/nvme*, erase SPI/MTD, or install a bootloader.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --template)
      template=${2:-}
      shift
      ;;
    --uboot)
      uboot=${2:-}
      shift
      ;;
    --output)
      output=${2:-}
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

[ -f "$template" ] || {
  printf 'ERROR: template package not found: %s\n' "$template" >&2
  exit 1
}
[ -f "$uboot" ] || {
  printf 'ERROR: U-Boot artifact not found: %s\n' "$uboot" >&2
  exit 1
}

if grep -aFq 'scan_dev_for_extlinux; run scan_dev_for_scripts' "$uboot"; then
  printf 'ERROR: U-Boot artifact still scans extlinux before scripts\n' >&2
  exit 1
fi
grep -aFq 'scan_dev_for_scripts; run scan_dev_for_extlinux' "$uboot" \
  || {
    printf 'ERROR: U-Boot artifact does not contain script-first distro scan order\n' >&2
    exit 1
  }
grep -aFq 'U-Boot Boot Menu' "$uboot" \
  || {
    printf 'ERROR: U-Boot artifact does not contain bootmenu support strings\n' >&2
    exit 1
  }
grep -aFq 'opi_bootselect' "$uboot" \
  || {
    printf 'ERROR: U-Boot artifact does not contain DM-video selector command\n' >&2
    exit 1
  }

mkdir -p "$(dirname "$output")"
"$repo_root/scripts/sunxi-toc1-package.py" repack \
  --template "$template" \
  --replace "u-boot=$uboot" \
  --output "$output"

"$repo_root/scripts/sunxi-toc1-package.py" inspect "$output"

grep -aFq 'scan_dev_for_scripts; run scan_dev_for_extlinux' "$output" \
  || {
    printf 'ERROR: output package does not contain script-first distro scan order\n' >&2
    exit 1
  }
grep -aFq 'U-Boot Boot Menu' "$output" \
  || {
    printf 'ERROR: output package does not contain bootmenu support strings\n' >&2
    exit 1
  }
grep -aFq 'opi_bootselect' "$output" \
  || {
    printf 'ERROR: output package does not contain DM-video selector command\n' >&2
    exit 1
  }

printf '\nPrepared file-only bootmenu package candidate:\n'
sha256sum "$output"
