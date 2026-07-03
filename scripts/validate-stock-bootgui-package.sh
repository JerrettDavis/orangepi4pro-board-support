#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package=

usage() {
  cat <<'USAGE'
Validate a stock-bootgui script-first Orange Pi 4 Pro TOC1 package.

Usage:
  scripts/validate-stock-bootgui-package.sh --package PACKAGE

The intended package is the vendor SD U-Boot with only the distro scan order
patched from extlinux-first to script-first. This validator is file-only.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --package)
      package=${2:-}
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

[ -n "$package" ] || {
  printf 'ERROR: --package is required\n' >&2
  usage >&2
  exit 2
}
[ -r "$package" ] || {
  printf 'ERROR: package is not readable: %s\n' "$package" >&2
  exit 1
}

"$repo_root/scripts/sunxi-toc1-package.py" inspect "$package" >/dev/null

python3 - "$repo_root" "$package" <<'PY'
from pathlib import Path
import importlib.util
import hashlib
import sys

repo_root = Path(sys.argv[1])
package_path = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location(
    "sunxi_toc1_package",
    repo_root / "scripts" / "sunxi-toc1-package.py",
)
toc = importlib.util.module_from_spec(spec)
sys.modules["sunxi_toc1_package"] = toc
spec.loader.exec_module(toc)

package = toc.read_package(package_path)
items = {item.name: item for item in package.items}
if set(items) != {"u-boot", "monitor", "scp"}:
    raise SystemExit(f"unexpected TOC1 items: {sorted(items)}")

uboot_item = items["u-boot"]
uboot = package.data[uboot_item.data_offset : uboot_item.data_offset + uboot_item.data_len]

old = b"run scan_dev_for_extlinux; run scan_dev_for_scripts"
new = b"run scan_dev_for_scripts; run scan_dev_for_extlinux"
if uboot.count(old) != 0:
    raise SystemExit("stock extlinux-first scan order is still present")
if uboot.count(new) != 1:
    raise SystemExit("script-first scan order is not present exactly once")

required = {
    b"sunxi_show_logo": "DRM logo command",
    b"boot.bmp": "factory boot.bmp loader strings",
    b"bootlogo": "BootGUI bootlogo strings",
    b"run scan_dev_for_scripts; run scan_dev_for_extlinux": "script-first scan order",
}
for needle, label in required.items():
    if needle not in uboot:
        raise SystemExit(f"missing {label}")

for forbidden in (b"opi_bootselect", b"opi_hdmi_pattern_diag", b"BOOTLOADER TEST SCREEN"):
    if forbidden in uboot:
        raise SystemExit(f"custom selector/debug U-Boot payload leaked in: {forbidden!r}")

print(f"package={package_path}")
print(f"sha256={hashlib.sha256(package.data).hexdigest()}")
print(f"u_boot_sha256={hashlib.sha256(uboot).hexdigest()}")
print(f"u_boot_length={len(uboot)}")
print(f"boot_bmp_string_count={uboot.count(b'boot.bmp')}")
print("stock BootGUI script-first package validation passed")
PY
