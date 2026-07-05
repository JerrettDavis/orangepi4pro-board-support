#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package=
profile=report
device=
seek_blocks=2050
block_size=8192
require_hdmi_dtb_aliases=false
require_embedded_boot_bmp=false
require_dvi_gate=false

usage() {
  cat <<'USAGE'
Inspect an Orange Pi 4 Pro TOC1 package for bootloader visual-path risk.

Usage:
  scripts/validate-boot-package-visual-path.sh --package FILE [--profile report|safe-baseline|script-first|fastlogo-scriptfirst] [--require-hdmi-dtb-aliases] [--require-embedded-boot-bmp] [--require-dvi-gate] [--device /dev/mmcblk1]

Profiles:
  report         Print package metadata and visual-path string findings only.
  safe-baseline Require vendor extlinux-first scan order, AW DRM logo support,
                and no known unsafe display-reinit paths.
  script-first  Require script-first scan order, AW DRM logo support, and no
                known unsafe display-reinit paths.
  fastlogo-scriptfirst
                Require script-first scan order, the vendor direct-register
                fastlogo path, the local fastlogo diagnostic marker, and no
                AW DRM logo path or known unsafe display-reinit paths.

When --device is provided, the script also verifies that the SD TOC1 slot at
bs=8192 seek=2050 byte-matches the package.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --package)
      package=${2:-}
      shift
      ;;
    --profile)
      profile=${2:-}
      shift
      ;;
    --device)
      device=${2:-}
      shift
      ;;
    --require-hdmi-dtb-aliases)
      require_hdmi_dtb_aliases=true
      ;;
    --require-embedded-boot-bmp)
      require_embedded_boot_bmp=true
      ;;
    --require-dvi-gate)
      require_dvi_gate=true
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

[ -n "$package" ] || fail '--package is required'
[ -f "$package" ] || fail "package not found: $package"
case "$profile" in
  report|safe-baseline|script-first|fastlogo-scriptfirst) ;;
  *) fail "--profile must be report, safe-baseline, script-first, or fastlogo-scriptfirst" ;;
esac

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
uboot_item="$tmpdir/u-boot.bin"
inspect_json="$tmpdir/inspect.json"

"$repo_root/scripts/sunxi-toc1-package.py" inspect --json "$package" > "$inspect_json"
PACKAGE="$package" INSPECT_JSON="$inspect_json" UBOOT_ITEM="$uboot_item" python3 - <<'PY'
import json
import os
import pathlib

package_path = pathlib.Path(os.environ["PACKAGE"])
summary_path = pathlib.Path(os.environ["INSPECT_JSON"])
uboot_path = pathlib.Path(os.environ["UBOOT_ITEM"])
summary = json.loads(summary_path.read_text())
items = {item["name"]: item for item in summary["items"]}
if "u-boot" not in items:
    raise SystemExit("ERROR: package has no u-boot item")
item = items["u-boot"]
data = package_path.read_bytes()
start = int(item["offset"])
end = start + int(item["length"])
uboot_path.write_bytes(data[start:end])
PY

package_sha=$(sha256sum "$package" | awk '{print $1}')
uboot_sha=$(sha256sum "$uboot_item" | awk '{print $1}')
package_size=$(stat -c '%s' "$package")

stock_scan='run scan_dev_for_extlinux; run scan_dev_for_scripts'
script_scan='run scan_dev_for_scripts; run scan_dev_for_extlinux'
stock_scan_count=$( (grep -a -F -o "$stock_scan" "$uboot_item" || true) | wc -l)
script_scan_count=$( (grep -a -F -o "$script_scan" "$uboot_item" || true) | wc -l)

has_aw_drm=false
has_bootgui=false
has_fastlogo=false
has_fastlogo_diag=false
has_unsafe=false
has_hdmi_dtb_aliases=false
has_embedded_boot_bmp=false
has_dvi_gate=false

if grep -a -Fq 'sunxi_show_logo' "$uboot_item"; then
  has_aw_drm=true
fi
if grep -a -Eq 'boot_gui_init|boot_gui_test|show_bmp_on_fb' "$uboot_item"; then
  has_bootgui=true
fi
if grep -a -Eq 'LogoRegData.bin|create_fastlogo_inst|display_fastlogo|bootlogo.bmp' "$uboot_item"; then
  has_fastlogo=true
fi
if grep -a -Fq 'opi_fastlogo_diag' "$uboot_item"; then
  has_fastlogo_diag=true
fi
if grep -a -Fq 'boot.bmp decompressed OK' "$uboot_item" \
  && grep -a -Fq 'embedded boot.bmp array' "$uboot_item"; then
  has_embedded_boot_bmp=true
fi
if grep -a -Fq 'clk_tcon_tv' "$uboot_item" \
  && grep -a -Fq 'clk_bus_hdmi' "$uboot_item" \
  && grep -a -Fq 'clk_tcon' "$uboot_item" \
  && grep -a -Fq 'rst_bus_tcon' "$uboot_item"; then
  has_hdmi_dtb_aliases=true
fi
if grep -a -Fq 'cyberdeck force DVI output mode' "$uboot_item" \
  && grep -a -Fq 'opi_hdmi_dvi_diag' "$uboot_item"; then
  has_dvi_gate=true
fi

unsafe_strings=(
  'sunxi_drm_reinit_active'
  '_sunxi_hdmi_reinit_active_display'
  'stale HDMI before logo'
  'HDMI still unlocked after logo enable'
  'dw_phy_wait_rxsense'
  'PHY_STAT0_RX_SENSE_ALL_MASK'
  'force visible reinit'
  'hdmi drv stale enable state'
  'post-skip-locked'
  'sunxi_drm_hdmi_recycle'
  'sunxi_drm hdmi_recycle'
)

printf 'package=%s\n' "$package"
printf 'package_sha256=%s\n' "$package_sha"
printf 'package_size=%s\n' "$package_size"
printf 'u_boot_sha256=%s\n' "$uboot_sha"
printf 'profile=%s\n' "$profile"
printf 'stock_scan_count=%s\n' "$stock_scan_count"
printf 'script_first_scan_count=%s\n' "$script_scan_count"
printf 'has_aw_drm_sunxi_show_logo=%s\n' "$has_aw_drm"
printf 'has_bootgui_symbols=%s\n' "$has_bootgui"
printf 'has_fastlogo_strings=%s\n' "$has_fastlogo"
printf 'has_fastlogo_diag=%s\n' "$has_fastlogo_diag"
printf 'has_embedded_boot_bmp=%s\n' "$has_embedded_boot_bmp"
printf 'has_hdmi_dtb_clock_aliases=%s\n' "$has_hdmi_dtb_aliases"
printf 'has_dvi_force_gate=%s\n' "$has_dvi_gate"

for unsafe in "${unsafe_strings[@]}"; do
  if grep -a -Fq "$unsafe" "$uboot_item"; then
    printf 'unsafe_string=%s\n' "$unsafe"
    has_unsafe=true
  fi
done
printf 'has_unsafe_visual_path=%s\n' "$has_unsafe"

case "$package_sha" in
  34f52a23883a427d6471bdfc69654ef853a6f96a1f406a732acd64a35555852f|\
  dac4949d4e5ad3fdb8c3db0bf16811f2ce8ed4948c242ffeebe3c052d940f7a1|\
  feacc7a99a48a1f6a64318b8372042f0b24df36bc5bae1f35f4bcc36581e6438|\
  6aa7b8590cf7d2b7b259aa08326a43d342c7ce6b0d233bc3e4faf5cbb3e46cd1)
    has_unsafe=true
    printf 'known_unsafe_package=true\n'
    ;;
  *)
    printf 'known_unsafe_package=false\n'
    ;;
esac

if [ -n "$device" ]; then
  [ -b "$device" ] || fail "not a block device: $device"
  verify_blocks=$(((package_size + block_size - 1) / block_size))
  readback="$tmpdir/current-toc1-slot.bin"
  dd if="$device" of="$readback" bs="$block_size" skip="$seek_blocks" count="$verify_blocks" status=none
  cmp -n "$package_size" "$package" "$readback" \
    || fail "$device TOC1 slot does not byte-match package"
  printf 'device_toc1_slot_matches=true\n'
fi

if [ "$has_unsafe" = true ]; then
  fail 'package contains a known unsafe visual path or hash'
fi
if [ "$require_hdmi_dtb_aliases" = true ] && [ "$has_hdmi_dtb_aliases" != true ]; then
  fail 'package is missing required HDMI/TCON DTB clock aliases'
fi
if [ "$require_embedded_boot_bmp" = true ] && [ "$has_embedded_boot_bmp" != true ]; then
  fail 'package is missing required embedded boot.bmp path'
fi
if [ "$require_dvi_gate" = true ] && [ "$has_dvi_gate" != true ]; then
  fail 'package is missing required DVI force gate'
fi

case "$profile" in
  safe-baseline)
    [ "$stock_scan_count" = 1 ] || fail 'safe-baseline requires exactly one extlinux-first scan order'
    [ "$script_scan_count" = 0 ] || fail 'safe-baseline must not contain script-first scan order'
    [ "$has_aw_drm" = true ] || fail 'safe-baseline requires AW DRM sunxi_show_logo support'
    ;;
  script-first)
    [ "$script_scan_count" = 1 ] || fail 'script-first requires exactly one script-first scan order'
    [ "$stock_scan_count" = 0 ] || fail 'script-first must not contain stock extlinux-first scan order'
    [ "$has_aw_drm" = true ] || fail 'script-first requires AW DRM sunxi_show_logo support'
    ;;
  fastlogo-scriptfirst)
    [ "$script_scan_count" = 1 ] || fail 'fastlogo-scriptfirst requires exactly one script-first scan order'
    [ "$stock_scan_count" = 0 ] || fail 'fastlogo-scriptfirst must not contain stock extlinux-first scan order'
    [ "$has_fastlogo" = true ] || fail 'fastlogo-scriptfirst requires vendor fastlogo strings'
    [ "$has_fastlogo_diag" = true ] || fail 'fastlogo-scriptfirst requires opi_fastlogo_diag marker'
    [ "$has_aw_drm" = false ] || fail 'fastlogo-scriptfirst must not contain AW DRM sunxi_show_logo support'
    ;;
esac

printf 'Boot package visual-path validation passed.\n'
