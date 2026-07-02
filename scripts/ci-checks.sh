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
gcc -O2 -Wall -Wextra -Werror -o /tmp/qdtech-touch-x11 \
  packages/qdtech-touch-x11/bin/qdtech-touch-x11.c -lusb-1.0 -lX11 -lXtst
gcc -O2 -Wall -Wextra -Werror -o /tmp/qdtech-usb-dump \
  packages/qdtech-touch-x11/bin/qdtech-usb-dump.c -lusb-1.0
rm -f /tmp/qdtech-touch-x11 /tmp/qdtech-usb-dump

printf 'Scanning for obvious secret patterns...\n'
if grep -RInE '(BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|ghp_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|AKIA[0-9A-Z]{16}|password[[:space:]]*=|token[[:space:]]*=|secret[[:space:]]*=)' \
  --exclude-dir=.git .; then
  printf 'ERROR: possible secret pattern found\n' >&2
  exit 1
fi

printf 'Checking for committed binary artifacts...\n'
if find . -type f -not -path './.git/*' -exec file {} + | grep -E 'ELF|PE32 executable|Mach-O|ISO 9660|filesystem data'; then
  printf 'ERROR: binary artifact found\n' >&2
  exit 1
fi

printf 'CI checks passed.\n'

