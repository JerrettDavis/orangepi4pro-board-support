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
  scripts/prepare-sd-bootmenu-package.sh [--template FILE] [--uboot FILE] [--output FILE] [--embedded-logo]

Defaults:
  TEMPLATE=/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu.fex
  UBOOT=.build/u-boot/artifacts/bootmenu/u-boot-sun60iw2p1.bin
  OUTPUT=/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu-scriptfirst.fex

This script only creates and validates a package file. It does not run dd,
write /dev/mmcblk*, write /dev/nvme*, erase SPI/MTD, or install a bootloader.
USAGE
}

embedded_logo=false
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
    --embedded-logo)
      embedded_logo=true
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
if [ "$embedded_logo" = true ]; then
  grep -aFq 'sysboot' "$uboot" \
    || {
      printf 'ERROR: embedded-logo artifact does not contain sysboot support\n' >&2
      exit 1
    }
  grep -aFq 'extlinux.conf' "$uboot" \
    || {
      printf 'ERROR: embedded-logo artifact does not contain extlinux parser strings\n' >&2
      exit 1
    }
  grep -aFq 'embedded boot.bmp array' "$uboot" \
    || {
      printf 'ERROR: U-Boot artifact does not contain the embedded boot.bmp marker\n' >&2
      exit 1
    }
  grep -aFq 'boot.bmp decompressed OK' "$uboot" \
    || {
      printf 'ERROR: U-Boot artifact does not contain the vendor embedded-logo decompression path\n' >&2
      exit 1
    }
  if grep -aFq '/boot/boot1.bmp' "$uboot"; then
    printf 'ERROR: embedded-logo artifact still contains file-backed boot1.bmp loader\n' >&2
    exit 1
  fi
  if grep -aFq 'BOOTLOADER TEST SCREEN' "$uboot"; then
    printf 'ERROR: embedded-logo artifact still contains high-contrast DM-video selector screen\n' >&2
    exit 1
  fi
else
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
  if grep -aFq 'embedded boot.bmp array' "$uboot"; then
    printf 'ERROR: U-Boot artifact still contains the embedded boot.bmp fallback\n' >&2
    exit 1
  fi
  grep -aFq '/boot/boot1.bmp' "$uboot" \
    || {
      printf 'ERROR: U-Boot artifact does not contain A733 file-backed boot1.bmp loader\n' >&2
      exit 1
    }
  grep -aFq 'BOOTLOADER TEST SCREEN' "$uboot" \
    || {
      printf 'ERROR: U-Boot artifact does not contain high-contrast selector test screen\n' >&2
      exit 1
    }
fi

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
if [ "$embedded_logo" = true ]; then
  grep -aFq 'sysboot' "$output" \
    || {
      printf 'ERROR: embedded-logo output does not contain sysboot support\n' >&2
      exit 1
    }
  grep -aFq 'extlinux.conf' "$output" \
    || {
      printf 'ERROR: embedded-logo output does not contain extlinux parser strings\n' >&2
      exit 1
    }
  grep -aFq 'embedded boot.bmp array' "$output" \
    || {
      printf 'ERROR: output package does not contain the embedded boot.bmp marker\n' >&2
      exit 1
    }
  grep -aFq 'boot.bmp decompressed OK' "$output" \
    || {
      printf 'ERROR: output package does not contain the vendor embedded-logo decompression path\n' >&2
      exit 1
    }
  if grep -aFq '/boot/boot1.bmp' "$output"; then
    printf 'ERROR: embedded-logo output still contains file-backed boot1.bmp loader\n' >&2
    exit 1
  fi
  if grep -aFq 'BOOTLOADER TEST SCREEN' "$output"; then
    printf 'ERROR: embedded-logo output still contains high-contrast DM-video selector screen\n' >&2
    exit 1
  fi
else
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
  if grep -aFq 'embedded boot.bmp array' "$output"; then
    printf 'ERROR: output package still contains the embedded boot.bmp fallback\n' >&2
    exit 1
  fi
  grep -aFq '/boot/boot1.bmp' "$output" \
    || {
      printf 'ERROR: output package does not contain A733 file-backed boot1.bmp loader\n' >&2
      exit 1
    }
  grep -aFq 'BOOTLOADER TEST SCREEN' "$output" \
    || {
      printf 'ERROR: output package does not contain high-contrast selector test screen\n' >&2
      exit 1
    }
fi

printf '\nPrepared file-only bootmenu package candidate:\n'
sha256sum "$output"
