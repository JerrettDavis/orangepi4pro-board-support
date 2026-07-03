#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
vendor_package=${VENDOR_PACKAGE:-/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex}
uboot_override=${UBOOT:-}
output=${OUTPUT:-/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-hdmi-clock-only.fex}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

usage() {
  cat <<'USAGE'
Prepare a vendor SD U-Boot package with only embedded HDMI clock binding fixes.

Usage:
  scripts/prepare-vendor-sd-hdmi-clock-package.sh [--vendor PACKAGE] [--uboot FILE] [--output PACKAGE]

This is file-only. It:
  - uses the vendor TOC1 package as the monitor/SCP/template source;
  - uses --uboot as the replacement U-Boot item, or extracts the vendor item;
  - patches only the embedded U-Boot DTB HDMI clock bindings so clk_hdmi
    points at the programmable hdmi_tv clock and the original HDMI gate is
    exposed as clk_bus_hdmi;
  - leaves HDMI power rails, fast-output, route force-output, and mode tables
    untouched;
  - rebuilds the TOC1 checksum.

It does not write block devices, MTD, SPI, partitions, filesystems, or firmware.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --vendor)
      vendor_package=${2:-}
      shift
      ;;
    --uboot)
      uboot_override=${2:-}
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

[ -r "$vendor_package" ] || {
  printf 'ERROR: vendor package not readable: %s\n' "$vendor_package" >&2
  exit 1
}
if [ -n "$uboot_override" ] && [ ! -r "$uboot_override" ]; then
  printf 'ERROR: U-Boot override not readable: %s\n' "$uboot_override" >&2
  exit 1
fi

for cmd in fdtget fdtput fdtdump; do
  command -v "$cmd" >/dev/null 2>&1 || {
    printf 'ERROR: %s is required\n' "$cmd" >&2
    exit 1
  }
done

if [ -n "$uboot_override" ]; then
  cp "$uboot_override" "$work_dir/u-boot-input.bin"
else
  python3 - "$repo_root" "$vendor_package" "$work_dir/u-boot-input.bin" <<'PY'
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
fi

python3 - "$work_dir/u-boot-input.bin" "$work_dir/u-boot.dtb" "$work_dir/dtb-meta.env" <<'PY'
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

if fdtget "$work_dir/u-boot.dtb" /soc@3000000/hdmi0@5520000 clocks >/dev/null 2>&1; then
  soc_node=/soc@3000000
elif fdtget "$work_dir/u-boot.dtb" /soc/hdmi0@5520000 clocks >/dev/null 2>&1; then
  soc_node=/soc
else
  printf 'ERROR: could not locate HDMI node in embedded U-Boot DTB\n' >&2
  exit 1
fi

hdmi_node=$soc_node/hdmi0@5520000
tcon3_node=$soc_node/tcon3@5730000
hdmi_tv_node=/clocks/hdmi_tv
hdmi_gate_node=/clocks/hdmi_gate

read -r tcon3_clock _ < <(fdtget "$work_dir/u-boot.dtb" "$tcon3_node" clocks)
hdmi_gate_phandle=$(fdtget "$work_dir/u-boot.dtb" "$hdmi_gate_node" phandle)
hdmi_tv_phandle=$(fdtget "$work_dir/u-boot.dtb" "$hdmi_tv_node" phandle 2>/dev/null || true)
if [ -z "$hdmi_tv_phandle" ]; then
  hdmi_tv_phandle=0x2f1
  if fdtdump "$work_dir/u-boot.dtb" 2>/dev/null | grep -Eq "<0x0*2f1>"; then
    printf 'ERROR: chosen hdmi_tv phandle 0x2f1 already exists in embedded DTB\n' >&2
    exit 1
  fi
  fdtput -t x "$work_dir/u-boot.dtb" "$hdmi_tv_node" phandle "$hdmi_tv_phandle"
fi

read -r -a hdmi_clocks < <(fdtget "$work_dir/u-boot.dtb" "$hdmi_node" clocks)
read -r -a hdmi_clock_names < <(fdtget "$work_dir/u-boot.dtb" "$hdmi_node" clock-names)
hdmi_24m_clock=
rst_main_clock=
rst_sub_clock=
for i in "${!hdmi_clock_names[@]}"; do
  case "${hdmi_clock_names[$i]}" in
    clk_hdmi_24M)
      hdmi_24m_clock=${hdmi_clocks[$i]:-}
      ;;
    rst_main)
      rst_main_clock=${hdmi_clocks[$i]:-}
      ;;
    rst_sub)
      rst_sub_clock=${hdmi_clocks[$i]:-}
      ;;
  esac
done
if [ -z "$hdmi_24m_clock" ] || [ -z "$rst_main_clock" ] || [ -z "$rst_sub_clock" ]; then
  printf 'ERROR: could not map existing HDMI clock/reset bindings\n' >&2
  exit 1
fi

fdtput -t x "$work_dir/u-boot.dtb" "$hdmi_node" clocks \
  "$(printf '0x%x' "$tcon3_clock")" \
  "$(printf '0x%x' "$hdmi_tv_phandle")" \
  "$(printf '0x%x' "$hdmi_24m_clock")" \
  "$(printf '0x%x' "$hdmi_gate_phandle")" \
  "$(printf '0x%x' "$rst_main_clock")" \
  "$(printf '0x%x' "$rst_sub_clock")"
fdtput -t s "$work_dir/u-boot.dtb" "$hdmi_node" clock-names \
  clk_tcon_tv clk_hdmi clk_hdmi_24M clk_bus_hdmi rst_main rst_sub

test "$(fdtget "$work_dir/u-boot.dtb" "$hdmi_node" clock-names)" = "clk_tcon_tv clk_hdmi clk_hdmi_24M clk_bus_hdmi rst_main rst_sub" \
  || {
    printf 'ERROR: HDMI clock binding normalization did not stick\n' >&2
    exit 1
  }

python3 - "$work_dir/u-boot-input.bin" "$work_dir/u-boot.dtb" "$dtb_offset" "$dtb_size" "$work_dir/u-boot-hdmi-clock.bin" <<'PY'
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
        raise SystemExit(f"patched DTB grew past U-Boot item data: {dtb_size} -> {len(dtb_data)}")
    padding = data[padding_start:padding_end]
    if any(byte not in (0x00, 0xFF) for byte in padding):
        raise SystemExit(f"patched DTB grew into non-padding data: {dtb_size} -> {len(dtb_data)}")
    dst.write_bytes(data[:dtb_offset] + dtb_data + data[dtb_offset + len(dtb_data) :])
else:
    dst.write_bytes(data[:dtb_offset] + dtb_data + b"\0" * (dtb_size - len(dtb_data)) + data[dtb_offset + dtb_size :])
PY

grep -aFq 'sunxi_hdmi_env' "$work_dir/u-boot-hdmi-clock.bin" \
  || {
    printf 'ERROR: patched U-Boot dropped sunxi_hdmi_env diagnostic command\n' >&2
    exit 1
  }
grep -aFq 'sunxi_drm_env' "$work_dir/u-boot-hdmi-clock.bin" \
  || {
    printf 'ERROR: patched U-Boot dropped sunxi_drm_env diagnostic command\n' >&2
    exit 1
  }

mkdir -p "$(dirname "$output")"
"$repo_root/scripts/sunxi-toc1-package.py" repack \
  --template "$vendor_package" \
  --replace "u-boot=$work_dir/u-boot-hdmi-clock.bin" \
  --output "$output"

"$repo_root/scripts/sunxi-toc1-package.py" inspect "$output"
printf '\nPatched embedded U-Boot DTB HDMI clocks only:\n'
printf '  uboot_override=%s\n' "${uboot_override:-<vendor item>}"
printf '  clk_tcon_tv_phandle=%s\n' "$tcon3_clock"
printf '  clk_hdmi_phandle=%s\n' "$hdmi_tv_phandle"
printf '  clk_bus_hdmi_phandle=%s\n' "$hdmi_gate_phandle"
printf '  hdmi_24m_phandle=%s\n' "$hdmi_24m_clock"
printf '\nPrepared vendor SD HDMI-clock package:\n'
sha256sum "$output"
