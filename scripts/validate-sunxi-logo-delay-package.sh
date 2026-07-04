#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package=
require_diag=false

usage() {
  cat <<'USAGE'
Validate a script-first Orange Pi 4 Pro TOC1 package with delayed sunxi_show_logo.

Usage:
  scripts/validate-sunxi-logo-delay-package.sh --package PACKAGE [--require-diag]

This validator is file-only. It checks that the package keeps the vendor
embedded-logo path, scans boot scripts before extlinux, includes the
sunxi_show_logo HPD delay marker, and excludes U-Boot payload strings from
known failed HDMI recovery attempts.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --package)
      package=${2:-}
      shift
      ;;
    --require-diag)
      require_diag=true
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

python3 - "$repo_root" "$package" "$require_diag" <<'PY'
from pathlib import Path
import importlib.util
import hashlib
import sys

repo_root = Path(sys.argv[1])
package_path = Path(sys.argv[2])
require_diag = sys.argv[3] == "true"

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

old_scan = b"run scan_dev_for_extlinux; run scan_dev_for_scripts"
new_scan = b"run scan_dev_for_scripts; run scan_dev_for_extlinux"
if old_scan in uboot:
    raise SystemExit("stock extlinux-first scan order is still present")
if uboot.count(new_scan) != 1:
    raise SystemExit("script-first scan order is not present exactly once")

required = {
    b"Orange Pi 4 Pro: waiting 5 seconds before sunxi_show_logo": "logo-delay marker",
    b"sunxi_show_logo": "DRM logo command",
    b"boot.bmp decompressed OK": "vendor embedded boot.bmp path",
    b"embedded boot.bmp array": "vendor embedded boot.bmp marker",
    b"sysboot": "extlinux sysboot command",
    b"extlinux.conf": "extlinux parser path",
}
for needle, label in required.items():
    if needle not in uboot:
        raise SystemExit(f"missing {label}")

if require_diag:
    diag_required = {
        b"sunxi_drm_env": "DRM env diagnostic command",
        b"sunxi_hdmi_env": "HDMI env diagnostic command",
        b"opi_drm_diag": "DRM diagnostic environment marker",
        b"opi_hdmi_diag": "HDMI diagnostic environment marker",
    }
    for needle, label in diag_required.items():
        if needle not in uboot:
            raise SystemExit(f"missing {label}")

for forbidden in (
    b"dw_phy_wait_rxsense",
    b"sunxi_drm reinit",
    b"HDMI still unlocked after logo enable",
    b"post-skip-locked-rxsense",
    b"stale HDMI before logo",
    b"/boot/boot1.bmp",
    b"BOOTLOADER TEST SCREEN",
):
    if forbidden in uboot:
        raise SystemExit(f"known-risk payload string present: {forbidden!r}")

print(f"package={package_path}")
print(f"sha256={hashlib.sha256(package.data).hexdigest()}")
print(f"u_boot_sha256={hashlib.sha256(uboot).hexdigest()}")
print(f"u_boot_length={len(uboot)}")
print(f"require_diag={str(require_diag).lower()}")
print("sunxi_show_logo delay package validation passed")
PY
