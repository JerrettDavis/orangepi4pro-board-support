#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_url=${SOURCE_URL:-https://github.com/orangepi-xunlong/u-boot-orangepi.git}
source_branch=${SOURCE_BRANCH:-v2018.05-sun60iw2}
source_commit=${SOURCE_COMMIT:-b791be842935b27268ae3d00e943a9075495f30a}
source_dir=${SOURCE_DIR:-/var/cache/orangepi4pro-images/sources/u-boot-orangepi}
build_root=${BUILD_ROOT:-"$repo_root/.build/u-boot"}
work_dir=${WORK_DIR:-"$build_root/work"}
artifact_dir=${ARTIFACT_DIR:-"$build_root/artifacts"}
fragment=${FRAGMENT:-"$repo_root/configs/u-boot/orangepi4pro-bootmenu.fragment"}
bootmenu_patch=${BOOTMENU_PATCH:-"$repo_root/configs/u-boot/0001-distro-scan-scripts-before-extlinux.patch"}
display_diag_patch=${DISPLAY_DIAG_PATCH:-"$repo_root/configs/u-boot/0002-add-sunxi-drm-env-diag.patch"}
display_mode_patch=${DISPLAY_MODE_PATCH:-"$repo_root/configs/u-boot/0003-use-cyberdeck-hdmi-default-mode.patch"}
apply_display_mode_patch=${APPLY_DISPLAY_MODE_PATCH:-false}
display_fbtest_patch=${DISPLAY_FBTEST_PATCH:-"$repo_root/configs/u-boot/0004-add-sunxi-drm-fbtest-command.patch"}
bootgui_selector_patch=${BOOTGUI_SELECTOR_PATCH:-"$repo_root/configs/u-boot/0005-add-dm-video-selector-command.patch"}
bootgui_selector_all_displays_patch=${BOOTGUI_SELECTOR_ALL_DISPLAYS_PATCH:-"$repo_root/configs/u-boot/0006-draw-selector-on-all-drm-displays.patch"}
selector_logo_generator=${SELECTOR_LOGO_GENERATOR:-"$repo_root/scripts/generate-uboot-selector-logo.py"}
cross_compile=${CROSS_COMPILE:-arm-linux-gnueabi-}
jobs=${JOBS:-$(nproc)}
defconfig=${DEFCONFIG:-sun60iw2p1_t736_defconfig}

usage() {
  cat <<'USAGE'
Build the Orange Pi vendor U-Boot tree for sun60iw2 without flashing anything.

Usage: scripts/build-vendor-uboot.sh [--baseline|--bootmenu] [--selector-logo] [--clean]

Environment overrides:
  SOURCE_DIR       Existing local vendor tree. Default:
                   /var/cache/orangepi4pro-images/sources/u-boot-orangepi
  SOURCE_URL       Clone URL when SOURCE_DIR is missing.
  SOURCE_BRANCH    Vendor branch. Default: v2018.05-sun60iw2
  SOURCE_COMMIT    Expected commit.
  BUILD_ROOT       Work/artifact root. Default: .build/u-boot
  CROSS_COMPILE    Toolchain prefix. Default: arm-linux-gnueabi-
  DTC              Device tree compiler. Default: /usr/bin/dtc
  JOBS             make -j value. Default: nproc
  SELECTOR_LOGO_GENERATOR
                   Generator for embedded boot_bmp.h selector image.

The script writes only under BUILD_ROOT. It does not install, dd, flash SPI,
or write boot sectors.
USAGE
}

mode=bootmenu
clean=false
selector_logo=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --baseline)
      mode=baseline
      ;;
    --bootmenu)
      mode=bootmenu
      ;;
    --selector-logo)
      mode=bootmenu
      selector_logo=true
      ;;
    --clean)
      clean=true
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

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'ERROR: required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

require_cmd git
require_cmd make
require_cmd "${cross_compile}gcc"
require_cmd "${DTC:-/usr/bin/dtc}"

if [ "$clean" = true ]; then
  rm -rf "$work_dir" "$artifact_dir"
fi

mkdir -p "$build_root" "$artifact_dir"

if [ ! -d "$source_dir/.git" ]; then
  mkdir -p "$(dirname "$source_dir")"
  git clone --branch "$source_branch" "$source_url" "$source_dir"
fi

actual_commit=$(git -C "$source_dir" rev-parse HEAD)
if [ "$actual_commit" != "$source_commit" ]; then
  printf 'ERROR: source commit mismatch\n' >&2
  printf '  expected: %s\n' "$source_commit" >&2
  printf '  actual:   %s\n' "$actual_commit" >&2
  exit 1
fi

rm -rf "$work_dir"
git clone "$source_dir" "$work_dir"

make_common=(
  -C "$work_dir"
  "PWD=$work_dir"
  "CROSS_COMPILE=$cross_compile"
  "DTC=${DTC:-/usr/bin/dtc}"
  "KCFLAGS=-Wno-error"
  "LICHEE_CHIP_CONFIG_DIR=$artifact_dir/lichee-chip"
  "LICHEE_BUSSINESS=orangepi4pro"
  "LICHEE_PLAT_OUT=$artifact_dir/lichee-plat"
)

mkdir -p "$artifact_dir/lichee-chip/orangepi4pro/bin" "$artifact_dir/lichee-plat"

make "${make_common[@]}" "$defconfig"

if [ "$mode" = bootmenu ]; then
  if [ ! -r "$bootmenu_patch" ]; then
    printf 'ERROR: bootmenu source patch not readable: %s\n' "$bootmenu_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply "$bootmenu_patch"
  if [ ! -r "$display_diag_patch" ]; then
    printf 'ERROR: display diagnostic patch not readable: %s\n' "$display_diag_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply "$display_diag_patch"
  if [ "$apply_display_mode_patch" = true ]; then
    if [ ! -r "$display_mode_patch" ]; then
      printf 'ERROR: display mode patch not readable: %s\n' "$display_mode_patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply "$display_mode_patch"
  fi
  if [ ! -r "$display_fbtest_patch" ]; then
    printf 'ERROR: framebuffer visual test patch not readable: %s\n' "$display_fbtest_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$display_fbtest_patch"
  if [ ! -r "$bootgui_selector_patch" ]; then
    printf 'ERROR: boot GUI selector patch not readable: %s\n' "$bootgui_selector_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply "$bootgui_selector_patch"
  if [ ! -r "$bootgui_selector_all_displays_patch" ]; then
    printf 'ERROR: boot GUI all-displays patch not readable: %s\n' "$bootgui_selector_all_displays_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$bootgui_selector_all_displays_patch"
  if [ ! -r "$fragment" ]; then
    printf 'ERROR: config fragment not readable: %s\n' "$fragment" >&2
    exit 1
  fi
  (
    cd "$work_dir"
    CROSS_COMPILE="$cross_compile" ./scripts/kconfig/merge_config.sh .config "$fragment"
  )
  make "${make_common[@]}" olddefconfig
fi

artifact_mode=$mode
if [ "$selector_logo" = true ]; then
  if [ ! -x "$selector_logo_generator" ]; then
    printf 'ERROR: selector logo generator not executable: %s\n' "$selector_logo_generator" >&2
    exit 1
  fi
  "$selector_logo_generator" \
    --output "$work_dir/drivers/video/drm/boot_bmp.h" \
    --bmp-output "$artifact_dir/bootmenu-selector-logo/selector-boot.bmp"
  artifact_mode=bootmenu-selector-logo
fi

make "${make_common[@]}" -j"$jobs"

mkdir -p "$artifact_dir/$artifact_mode"
for artifact in \
  u-boot \
  u-boot.bin \
  u-boot.dtb \
  u-boot-dtb.bin \
  u-boot-nodtb.bin \
  u-boot-sun60iw2p1.bin \
  u-boot.cfg \
  u-boot.cfg.configs; do
  if [ -e "$work_dir/$artifact" ]; then
    cp -a "$work_dir/$artifact" "$artifact_dir/$artifact_mode/"
  fi
done

grep -E 'CONFIG_(CMD_BOOTMENU|AUTOBOOT_MENU_SHOW|USB_KEYBOARD|SYS_USB_EVENT_POLL|DM_KEYBOARD|EFI_LOADER|BOOTDELAY)=' \
  "$work_dir/.config" > "$artifact_dir/$artifact_mode/config-summary.txt" || true

cat > "$artifact_dir/$artifact_mode/SOURCE.txt" <<EOF
url=$source_url
branch=$source_branch
commit=$source_commit
defconfig=$defconfig
mode=$mode
selector_logo=$selector_logo
apply_display_mode_patch=$apply_display_mode_patch
cross_compile=$cross_compile
dtc=${DTC:-/usr/bin/dtc}
EOF

printf 'Built vendor U-Boot artifacts in %s/%s\n' "$artifact_dir" "$artifact_mode"
printf 'No install or flash action was performed.\n'
