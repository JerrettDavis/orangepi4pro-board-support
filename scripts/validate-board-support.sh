#!/usr/bin/env bash
set -euo pipefail

printf 'Board compatible strings:\n'
tr '\0' '\n' < /proc/device-tree/compatible 2>/dev/null || true

printf '\nKernel:\n'
uname -a

printf '\nRequired kernel options:\n'
if [ -r /proc/config.gz ]; then
  for opt in HID_MULTITOUCH HIDRAW UHID INPUT_UINPUT USB_HID INPUT_EVDEV BLK_DEV_NVME OVERLAY_FS TUN; do
    zgrep -E "CONFIG_${opt}=" /proc/config.gz || printf 'CONFIG_%s is not set or unavailable\n' "$opt"
  done
else
  printf '/proc/config.gz not readable\n'
fi

printf '\nNVMe devices:\n'
lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS /dev/nvme0n1 2>/dev/null || true

printf '\nRecent NVMe/PCIe messages:\n'
dmesg | grep -Ei 'nvme|pcie|pci ' | tail -80 || true

printf '\nDisplay state:\n'
if command -v xrandr >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
  xrandr --query || true
else
  printf 'xrandr unavailable or DISPLAY not set\n'
fi

printf '\nTouch fallback:\n'
test -f packages/qdtech-touch-x11/README.md && printf 'qdtech-touch-x11 source present\n' || printf 'qdtech-touch-x11 source missing\n'

