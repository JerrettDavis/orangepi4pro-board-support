#!/usr/bin/env bash
set -euo pipefail

out="${1:-research/private/stock-state-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$out"

uname -a > "$out/uname.txt"
tr '\0' '\n' < /proc/device-tree/compatible > "$out/device-tree-compatible.txt" 2>/dev/null || true
lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS > "$out/lsblk.txt"
dmesg > "$out/dmesg.txt"
lsusb > "$out/lsusb.txt" 2>/dev/null || true
lspci -vvv > "$out/lspci-vvv.txt" 2>/dev/null || true

if [ -r /proc/config.gz ]; then
  zcat /proc/config.gz > "$out/kernel-config.txt"
elif [ -r "/boot/config-$(uname -r)" ]; then
  cp "/boot/config-$(uname -r)" "$out/kernel-config.txt"
fi

cp -a /boot "$out/boot" 2>/dev/null || true
cp -a /home/orangepi/touchscreen-fix-src "$out/touchscreen-fix-src" 2>/dev/null || true

printf 'Captured stock state under %s\n' "$out"

