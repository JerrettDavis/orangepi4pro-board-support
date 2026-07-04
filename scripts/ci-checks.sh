#!/usr/bin/env bash
set -euo pipefail

printf 'Checking shell syntax...\n'
while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find scripts packages -type f -print0 | while IFS= read -r -d '' file; do
  if head -n 1 "$file" | grep -qE '^#!.*(bash|sh)'; then
    printf '%s\0' "$file"
  fi
done)

if command -v shellcheck >/dev/null 2>&1; then
  printf 'Running shellcheck...\n'
  shellcheck scripts/*.sh packages/qdtech-touch-x11/bin/install-touchscreen-xorg-fix packages/qdtech-touch-x11/bin/orangepi-touch-map
else
  printf 'shellcheck not installed; skipping optional shell lint\n'
fi

printf 'Compiling touch helper sources...\n'
tmp_build=$(mktemp -d)
trap 'rm -rf "$tmp_build"' EXIT
gcc -O2 -Wall -Wextra -Werror -o "$tmp_build/qdtech-touch-x11" \
  packages/qdtech-touch-x11/bin/qdtech-touch-x11.c -lusb-1.0 -lX11 -lXtst
gcc -O2 -Wall -Wextra -Werror -o "$tmp_build/qdtech-usb-dump" \
  packages/qdtech-touch-x11/bin/qdtech-usb-dump.c -lusb-1.0
gcc -O2 -Wall -Wextra -Werror -o "$tmp_build/orangepi-read-mmio" \
  tools/read-mmio.c

printf 'Running sunxi TOC1 package self-test...\n'
python3 -m py_compile scripts/sunxi-toc1-package.py scripts/generate-uboot-selector-logo.py
scripts/sunxi-toc1-package.py selftest
bash -n scripts/validate-stock-bootgui-package.sh
bash -n scripts/validate-sunxi-logo-delay-package.sh

if [ -f /usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex ]; then
  printf 'Validating known safe boot package visual path...\n'
  scripts/validate-boot-package-visual-path.sh \
    --package /usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex \
    --profile safe-baseline
fi
if [ -f /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-early-display-recycle.fex ]; then
  printf 'Checking unsafe HDMI recycle package remains blocked...\n'
  if scripts/validate-boot-package-visual-path.sh \
    --package /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-early-display-recycle.fex \
    --profile report >/dev/null 2>&1; then
    printf 'ERROR: known unsafe HDMI recycle package unexpectedly passed validation\n' >&2
    exit 1
  fi
fi

printf 'Scanning for obvious secret patterns...\n'
if grep -RInE '(BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|ghp_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|AKIA[0-9A-Z]{16}|password[[:space:]]*=|token[[:space:]]*=|secret[[:space:]]*=)' \
  --exclude-dir=.git \
  --exclude-dir=.build \
  --exclude-dir=build \
  --exclude-dir=downloads \
  --exclude-dir=out \
  --exclude-dir=research/private \
  .; then
  printf 'ERROR: possible secret pattern found\n' >&2
  exit 1
fi

printf 'Checking for committed binary artifacts...\n'
if find . \
  -path './.git' -prune -o \
  -path './.build' -prune -o \
  -path './build' -prune -o \
  -path './downloads' -prune -o \
  -path './out' -prune -o \
  -path './research/private' -prune -o \
  -type f -exec file {} + | grep -E 'ELF|PE32 executable|Mach-O|ISO 9660|filesystem data'; then
  printf 'ERROR: binary artifact found\n' >&2
  exit 1
fi

printf 'CI checks passed.\n'
