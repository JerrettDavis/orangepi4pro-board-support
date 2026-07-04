#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
vendor_package=${VENDOR_PACKAGE:-/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex}
output=${OUTPUT:-/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_vendor-nvme-scriptfirst.fex}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

usage() {
  cat <<'USAGE'
Prepare a script-first package from Orange Pi's packaged A733 U-Boot.

Usage:
  scripts/prepare-vendor-nvme-scriptfirst-package.sh [--vendor PACKAGE] [--output PACKAGE]

This is file-only. It patches the packaged vendor U-Boot binary in a
length-preserving way so scan_dev_for_boot runs boot.scr before extlinux, then
rebuilds the Allwinner TOC1 package checksum. It accepts both the vendor NVMe
package and the vendor SD package. It does not write block devices, MTD, SPI,
partitions, filesystems, or firmware.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --vendor)
      vendor_package=${2:-}
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

if [ ! -r "$vendor_package" ]; then
  printf 'ERROR: vendor package not readable: %s\n' "$vendor_package" >&2
  exit 1
fi

python3 - "$repo_root" "$vendor_package" "$work_dir/u-boot-vendor.bin" <<'PY'
from pathlib import Path
import importlib.util
import sys

repo_root = Path(sys.argv[1])
package_path = Path(sys.argv[2])
output_path = Path(sys.argv[3])

spec = importlib.util.spec_from_file_location(
    "sunxi_toc1_package",
    repo_root / "scripts" / "sunxi-toc1-package.py",
)
toc = importlib.util.module_from_spec(spec)
sys.modules["sunxi_toc1_package"] = toc
spec.loader.exec_module(toc)

package = toc.read_package(package_path)
for item in package.items:
    if item.name == "u-boot":
        output_path.write_bytes(
            package.data[item.data_offset : item.data_offset + item.data_len]
        )
        break
else:
    raise SystemExit("vendor package does not contain a u-boot item")
PY

python3 - "$work_dir/u-boot-vendor.bin" "$work_dir/u-boot-scriptfirst.bin" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
old = b"run scan_dev_for_extlinux; run scan_dev_for_scripts"
new = b"run scan_dev_for_scripts; run scan_dev_for_extlinux"
data = src.read_bytes()
count = data.count(old)
if count != 1:
    raise SystemExit(f"expected exactly one scan order string, found {count}")
if len(old) != len(new):
    raise SystemExit("replacement must be length-preserving")
dst.write_bytes(data.replace(old, new, 1))
PY

if grep -aFq 'bootcmd_nvme=' "$work_dir/u-boot-vendor.bin"; then
  grep -aFq 'bootcmd_nvme=' "$work_dir/u-boot-scriptfirst.bin" \
    || {
      printf 'ERROR: patched U-Boot lost vendor NVMe boot command\n' >&2
      exit 1
    }
else
  printf 'NOTE: vendor package has no bootcmd_nvme; SD boot script must load kernel assets.\n'
fi
grep -aFq 'boot.bmp decompressed OK' "$work_dir/u-boot-scriptfirst.bin" \
  || {
    printf 'ERROR: patched U-Boot does not preserve factory embedded-logo path\n' >&2
    exit 1
  }
grep -aFq 'run scan_dev_for_scripts; run scan_dev_for_extlinux' "$work_dir/u-boot-scriptfirst.bin" \
  || {
    printf 'ERROR: patched U-Boot does not contain script-first scan order\n' >&2
    exit 1
  }

mkdir -p "$(dirname "$output")"
"$repo_root/scripts/sunxi-toc1-package.py" repack \
  --template "$vendor_package" \
  --replace "u-boot=$work_dir/u-boot-scriptfirst.bin" \
  --output "$output"

"$repo_root/scripts/sunxi-toc1-package.py" inspect "$output"
"$repo_root/scripts/validate-boot-package-visual-path.sh" \
  --package "$output" \
  --profile script-first
printf '\nPrepared vendor NVMe script-first package:\n'
sha256sum "$output"
