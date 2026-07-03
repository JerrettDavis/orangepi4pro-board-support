#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
vendor_package=${VENDOR_PACKAGE:-/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package.fex}
output=${OUTPUT:-/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_vendor-sd-scriptfirst-hdmi-power.fex}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

usage() {
  cat <<'USAGE'
Prepare a vendor SD U-Boot package with script-first boot and corrected HDMI power.

Usage:
  scripts/prepare-vendor-sd-hdmi-power-package.sh [--vendor PACKAGE] [--output PACKAGE]

This is file-only. It:
  - extracts the vendor U-Boot item from an Allwinner TOC1 package;
  - patches distro boot scanning so boot.scr runs before extlinux;
  - patches the embedded U-Boot DTB so the HDMI driver sees the property names
    it actually reads: uhdmi_power_count, uhdmi_resistor_select, and
    uhdmi_fast_output;
  - adds a cldo2 regulator node matching the working Linux DTB and points
    hdmi_power1 at it by phandle;
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

for cmd in fdtget fdtput fdtdump; do
  command -v "$cmd" >/dev/null 2>&1 || {
    printf 'ERROR: %s is required\n' "$cmd" >&2
    exit 1
  }
done

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
old_count = data.count(old)
new_count = data.count(new)
if old_count == 1:
    if len(old) != len(new):
        raise SystemExit("replacement must be length-preserving")
    dst.write_bytes(data.replace(old, new, 1))
elif old_count == 0 and new_count >= 1:
    dst.write_bytes(data)
else:
    raise SystemExit(
        f"expected one stock scan-order string or an already patched U-Boot, "
        f"found old={old_count} new={new_count}"
    )
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
if fdtget "$work_dir/u-boot.dtb" /soc@3000000/hdmi0@5520000 dcdc2-supply >/dev/null 2>&1; then
  soc_node=/soc@3000000
elif fdtget "$work_dir/u-boot.dtb" /soc/hdmi0@5520000 dcdc2-supply >/dev/null 2>&1; then
  soc_node=/soc
else
  printf 'ERROR: could not locate HDMI node in embedded U-Boot DTB\n' >&2
  exit 1
fi

hdmi_node=$soc_node/hdmi0@5520000
if fdtget -l "$work_dir/u-boot.dtb" "$soc_node/twi@7083000/pmu@36/regulators@0" >/dev/null 2>&1; then
  regulators_node=$soc_node/twi@7083000/pmu@36/regulators@0
elif fdtget -l "$work_dir/u-boot.dtb" "$soc_node/pmu@36/regulators@0" >/dev/null 2>&1; then
  regulators_node=$soc_node/pmu@36/regulators@0
elif fdtget -l "$work_dir/u-boot.dtb" /soc@29000000/pinctrl@0300b000/s_twi@0x07083000/pmu@36/regulators@0 >/dev/null 2>&1; then
  regulators_node=/soc@29000000/pinctrl@0300b000/s_twi@0x07083000/pmu@36/regulators@0
else
  printf 'ERROR: could not locate AXP8191 regulators node in embedded U-Boot DTB\n' >&2
  exit 1
fi
cldo2_node=$regulators_node/cldo2

dcdc2_phandle=$(fdtget "$work_dir/u-boot.dtb" "$hdmi_node" dcdc2-supply)
cldo2_phandle=0x2f0

if fdtdump "$work_dir/u-boot.dtb" 2>/dev/null | grep -Eq "<0x0*2f0>"; then
  printf 'ERROR: chosen cldo2 phandle 0x2f0 already exists in embedded DTB\n' >&2
  exit 1
fi

fdtput -c "$work_dir/u-boot.dtb" "$cldo2_node"
fdtput -t s "$work_dir/u-boot.dtb" "$cldo2_node" regulator-name axp8191-cldo2
fdtput -t x "$work_dir/u-boot.dtb" "$cldo2_node" regulator-min-microvolt 0x7a120
fdtput -t x "$work_dir/u-boot.dtb" "$cldo2_node" regulator-max-microvolt 0x3567e0
fdtput -t x "$work_dir/u-boot.dtb" "$cldo2_node" regulator-enable-ramp-delay 0x3e8
fdtput "$work_dir/u-boot.dtb" "$cldo2_node" regulator-boot-on
fdtput "$work_dir/u-boot.dtb" "$cldo2_node" regulator-always-on
fdtput -t x "$work_dir/u-boot.dtb" "$cldo2_node" phandle "$cldo2_phandle"

fdtput -t x "$work_dir/u-boot.dtb" "$hdmi_node" cldo2-supply "$cldo2_phandle"
fdtput -t x "$work_dir/u-boot.dtb" "$hdmi_node" hdmi_power0 "$(printf '0x%x' "$dcdc2_phandle")"
fdtput -t x "$work_dir/u-boot.dtb" "$hdmi_node" hdmi_power1 "$cldo2_phandle"
fdtput -t x "$work_dir/u-boot.dtb" "$hdmi_node" uhdmi_power_count 0x2
fdtput -t x "$work_dir/u-boot.dtb" "$hdmi_node" uhdmi_resistor_select 0x1
fdtput -t x "$work_dir/u-boot.dtb" "$hdmi_node" uhdmi_fast_output 0x0

test "$(fdtget "$work_dir/u-boot.dtb" "$cldo2_node" regulator-name)" = "axp8191-cldo2" \
  || {
    printf 'ERROR: cldo2 regulator node was not created correctly\n' >&2
    exit 1
  }
test "$(fdtget "$work_dir/u-boot.dtb" "$hdmi_node" hdmi_power0)" = "$dcdc2_phandle" \
  || {
    printf 'ERROR: hdmi_power0 phandle patch did not stick\n' >&2
    exit 1
  }
test "$(fdtget "$work_dir/u-boot.dtb" "$hdmi_node" hdmi_power1)" = "752" \
  || {
    printf 'ERROR: hdmi_power1 phandle patch did not stick\n' >&2
    exit 1
  }
test "$(fdtget "$work_dir/u-boot.dtb" "$hdmi_node" uhdmi_power_count)" = "2" \
  || {
    printf 'ERROR: uhdmi_power_count patch did not stick\n' >&2
    exit 1
  }

python3 - "$work_dir/u-boot-scriptfirst.bin" "$work_dir/u-boot.dtb" "$dtb_offset" "$dtb_size" "$work_dir/u-boot-hdmi-power.bin" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dtb = Path(sys.argv[2])
dtb_offset = int(sys.argv[3])
dtb_size = int(sys.argv[4])
dst = Path(sys.argv[5])
data = src.read_bytes()
dtb_data = dtb.read_bytes()
if len(dtb_data) > dtb_size:
    extra = len(dtb_data) - dtb_size
    padding_start = dtb_offset + dtb_size
    padding_end = padding_start + extra
    if padding_start == len(data):
        dst.write_bytes(data[:dtb_offset] + dtb_data)
        raise SystemExit(0)
    if padding_end > len(data):
        raise SystemExit(
            f"patched DTB grew past non-terminal U-Boot item data: "
            f"{dtb_size} -> {len(dtb_data)}"
        )
    padding = data[padding_start:padding_end]
    if any(byte not in (0x00, 0xFF) for byte in padding):
        raise SystemExit(f"patched DTB grew into non-padding data: {dtb_size} -> {len(dtb_data)}")
    dst.write_bytes(data[:dtb_offset] + dtb_data + data[dtb_offset + len(dtb_data) :])
else:
    dst.write_bytes(data[:dtb_offset] + dtb_data + b"\0" * (dtb_size - len(dtb_data)) + data[dtb_offset + dtb_size :])
PY

if ! grep -aFq 'boot.bmp decompressed OK' "$work_dir/u-boot-hdmi-power.bin" \
  && ! grep -aFq '/boot/boot1.bmp' "$work_dir/u-boot-hdmi-power.bin"; then
  printf 'ERROR: patched U-Boot does not preserve a known boot logo path\n' >&2
  exit 1
fi
grep -aFq 'run scan_dev_for_scripts; run scan_dev_for_extlinux' "$work_dir/u-boot-hdmi-power.bin" \
  || {
    printf 'ERROR: patched U-Boot does not contain script-first scan order\n' >&2
    exit 1
  }

mkdir -p "$(dirname "$output")"
"$repo_root/scripts/sunxi-toc1-package.py" repack \
  --template "$vendor_package" \
  --replace "u-boot=$work_dir/u-boot-hdmi-power.bin" \
  --output "$output"

"$repo_root/scripts/sunxi-toc1-package.py" inspect "$output"
printf '\nPatched embedded U-Boot DTB HDMI power:\n'
printf '  dcdc2_phandle=%s\n' "$dcdc2_phandle"
printf '  cldo2_phandle=%s\n' "$cldo2_phandle"
printf '  uhdmi_power_count=2\n'
printf '\nPrepared vendor SD HDMI-power package:\n'
sha256sum "$output"
