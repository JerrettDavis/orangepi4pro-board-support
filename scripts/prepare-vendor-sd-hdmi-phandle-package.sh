#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
vendor_package=${VENDOR_PACKAGE:-/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package.fex}
output=${OUTPUT:-/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_vendor-sd-scriptfirst-hdmi-phandles.fex}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

usage() {
  cat <<'USAGE'
Prepare a vendor SD U-Boot package with script-first boot and HDMI regulator phandles.

Usage:
  scripts/prepare-vendor-sd-hdmi-phandle-package.sh [--vendor PACKAGE] [--output PACKAGE]

This is file-only. It:
  - extracts the vendor U-Boot item from an Allwinner TOC1 package;
  - patches distro boot scanning so boot.scr runs before extlinux;
  - patches the embedded U-Boot DTB so hdmi_power0/hdmi_power1 are phandles
    to the existing dcdc2-supply/dldo2-supply regulators instead of strings;
  - rebuilds the package checksum.

It does not write block devices, MTD, SPI, partitions, filesystems, or firmware.
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

command -v fdtget >/dev/null 2>&1 || {
  printf 'ERROR: fdtget is required\n' >&2
  exit 1
}
command -v fdtput >/dev/null 2>&1 || {
  printf 'ERROR: fdtput is required\n' >&2
  exit 1
}

python3 - "$repo_root" "$vendor_package" "$work_dir/u-boot-vendor.bin" <<'PY'
from pathlib import Path
import importlib.util
import sys

sys.dont_write_bytecode = True
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

python3 - "$work_dir/u-boot-scriptfirst.bin" "$work_dir/u-boot.dtb" "$work_dir/dtb-meta.env" <<'PY'
from pathlib import Path
import struct
import sys

uboot_path = Path(sys.argv[1])
dtb_path = Path(sys.argv[2])
meta_path = Path(sys.argv[3])
data = uboot_path.read_bytes()
magic = b"\xd0\x0d\xfe\xed"
candidates = []
offset = 0
while True:
    offset = data.find(magic, offset)
    if offset < 0:
        break
    if offset + 8 <= len(data):
        size = struct.unpack(">I", data[offset + 4 : offset + 8])[0]
        if 0 < size <= len(data) - offset:
            candidates.append((offset, size))
    offset += 4
if not candidates:
    raise SystemExit("no embedded DTB found in U-Boot item")
dtb_offset, dtb_size = candidates[-1]
dtb_path.write_bytes(data[dtb_offset : dtb_offset + dtb_size])
meta_path.write_text(f"dtb_offset={dtb_offset}\ndtb_size={dtb_size}\n", encoding="ascii")
PY

dtb_offset=$(awk -F= '$1 == "dtb_offset" { print $2 }' "$work_dir/dtb-meta.env")
dtb_size=$(awk -F= '$1 == "dtb_size" { print $2 }' "$work_dir/dtb-meta.env")
hdmi_node=/soc/hdmi0@5520000
dcdc2_phandle=$(fdtget "$work_dir/u-boot.dtb" "$hdmi_node" dcdc2-supply)
dldo2_phandle=$(fdtget "$work_dir/u-boot.dtb" "$hdmi_node" dldo2-supply)

if [ -z "$dcdc2_phandle" ] || [ -z "$dldo2_phandle" ]; then
  printf 'ERROR: could not read HDMI supply phandles from embedded U-Boot DTB\n' >&2
  exit 1
fi

dcdc2_hex=$(printf '0x%x' "$dcdc2_phandle")
dldo2_hex=$(printf '0x%x' "$dldo2_phandle")

fdtput -t x "$work_dir/u-boot.dtb" "$hdmi_node" hdmi_power0 "$dcdc2_hex"
fdtput -t x "$work_dir/u-boot.dtb" "$hdmi_node" hdmi_power1 "$dldo2_hex"

test "$(fdtget "$work_dir/u-boot.dtb" "$hdmi_node" hdmi_power0)" = "$dcdc2_phandle" \
  || {
    printf 'ERROR: hdmi_power0 phandle patch did not stick\n' >&2
    exit 1
  }
test "$(fdtget "$work_dir/u-boot.dtb" "$hdmi_node" hdmi_power1)" = "$dldo2_phandle" \
  || {
    printf 'ERROR: hdmi_power1 phandle patch did not stick\n' >&2
    exit 1
  }

python3 - "$work_dir/u-boot-scriptfirst.bin" "$work_dir/u-boot.dtb" "$dtb_offset" "$dtb_size" "$work_dir/u-boot-scriptfirst-hdmi.bin" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dtb = Path(sys.argv[2])
dtb_offset = int(sys.argv[3])
dtb_size = int(sys.argv[4])
dst = Path(sys.argv[5])
data = src.read_bytes()
dtb_data = dtb.read_bytes()
dst.write_bytes(data[:dtb_offset] + dtb_data + data[dtb_offset + dtb_size :])
PY

grep -aFq 'boot.bmp decompressed OK' "$work_dir/u-boot-scriptfirst-hdmi.bin" \
  || {
    printf 'ERROR: patched U-Boot does not preserve factory embedded-logo path\n' >&2
    exit 1
  }
grep -aFq 'run scan_dev_for_scripts; run scan_dev_for_extlinux' "$work_dir/u-boot-scriptfirst-hdmi.bin" \
  || {
    printf 'ERROR: patched U-Boot does not contain script-first scan order\n' >&2
    exit 1
  }

mkdir -p "$(dirname "$output")"
"$repo_root/scripts/sunxi-toc1-package.py" repack \
  --template "$vendor_package" \
  --replace "u-boot=$work_dir/u-boot-scriptfirst-hdmi.bin" \
  --output "$output"

"$repo_root/scripts/sunxi-toc1-package.py" inspect "$output"
printf '\nPatched embedded U-Boot DTB HDMI regulator phandles:\n'
printf '  hdmi_power0=%s\n' "$dcdc2_phandle"
printf '  hdmi_power1=%s\n' "$dldo2_phandle"
printf '\nPrepared vendor SD script-first HDMI-phandle package:\n'
sha256sum "$output"
