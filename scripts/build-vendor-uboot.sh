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
bootgui_fragment=${BOOTGUI_FRAGMENT:-"$repo_root/configs/u-boot/orangepi4pro-bootgui.fragment"}
awdrm_bootgui_fragment=${AWDRM_BOOTGUI_FRAGMENT:-"$repo_root/configs/u-boot/orangepi4pro-awdrm-bootgui.fragment"}
bootmenu_patch=${BOOTMENU_PATCH:-"$repo_root/configs/u-boot/0001-distro-scan-scripts-before-extlinux.patch"}
display_diag_patch=${DISPLAY_DIAG_PATCH:-"$repo_root/configs/u-boot/0002-add-sunxi-drm-env-diag.patch"}
display_mode_patch=${DISPLAY_MODE_PATCH:-"$repo_root/configs/u-boot/0003-use-cyberdeck-hdmi-default-mode.patch"}
apply_display_mode_patch=${APPLY_DISPLAY_MODE_PATCH:-true}
display_fbtest_patch=${DISPLAY_FBTEST_PATCH:-"$repo_root/configs/u-boot/0004-add-sunxi-drm-fbtest-command.patch"}
bootgui_selector_patch=${BOOTGUI_SELECTOR_PATCH:-"$repo_root/configs/u-boot/0005-add-dm-video-selector-command.patch"}
bootgui_selector_all_displays_patch=${BOOTGUI_SELECTOR_ALL_DISPLAYS_PATCH:-"$repo_root/configs/u-boot/0006-draw-selector-on-all-drm-displays.patch"}
a733_logo_loader_patch=${A733_LOGO_LOADER_PATCH:-"$repo_root/configs/u-boot/0007-use-a733-file-backed-boot-logo.patch"}
high_contrast_selector_patch=${HIGH_CONTRAST_SELECTOR_PATCH:-"$repo_root/configs/u-boot/0008-use-high-contrast-selector-test-screen.patch"}
hdmi_diag_patch=${HDMI_DIAG_PATCH:-"$repo_root/configs/u-boot/0009-add-sunxi-hdmi-env-diag.patch"}
hdmi_mode_clock_patch=${HDMI_MODE_CLOCK_PATCH:-"$repo_root/configs/u-boot/0010-use-hdmi-mode-clock-when-tcon-rate-is-stale.patch"}
hdmi_bus_clock_patch=${HDMI_BUS_CLOCK_PATCH:-"$repo_root/configs/u-boot/0011-enable-hdmi-bus-clock.patch"}
hdmi_pattern_status_patch=${HDMI_PATTERN_STATUS_PATCH:-"$repo_root/configs/u-boot/0012-fix-hdmi-pattern-status-diag.patch"}
hdmi_top_phy_pddq_patch=${HDMI_TOP_PHY_PDDQ_PATCH:-"$repo_root/configs/u-boot/0013-clear-top-phy-pddq-on-power-on.patch"}
hdmi_pattern_reconfig_patch=${HDMI_PATTERN_RECONFIG_PATCH:-"$repo_root/configs/u-boot/0014-reconfigure-hdmi-before-pattern-test.patch"}
hdmi_pattern_full_reinit_patch=${HDMI_PATTERN_FULL_REINIT_PATCH:-"$repo_root/configs/u-boot/0015-full-hdmi-reinit-before-pattern-test.patch"}
hdmi_reinit_stage_diag_patch=${HDMI_REINIT_STAGE_DIAG_PATCH:-"$repo_root/configs/u-boot/0016-add-hdmi-reinit-stage-diagnostics.patch"}
drm_reinit_visual_diag_patch=${DRM_REINIT_VISUAL_DIAG_PATCH:-"$repo_root/configs/u-boot/0017-add-drm-reinit-visual-diagnostic.patch"}
tcon_hdmi_clock_sequence_patch=${TCON_HDMI_CLOCK_SEQUENCE_PATCH:-"$repo_root/configs/u-boot/0018-use-linux-like-hdmi-tcon-clock-sequence.patch"}
hdmi_fc_iteration_patch=${HDMI_FC_ITERATION_PATCH:-"$repo_root/configs/u-boot/0019-sync-linux-hdmi-fc-iteration-and-diag.patch"}
hdmi_phy_rxsense_patch=${HDMI_PHY_RXSENSE_PATCH:-"$repo_root/configs/u-boot/0020-wait-for-snps-phy-rxsense.patch"}
hdmi_top_phy_autocal_patch=${HDMI_TOP_PHY_AUTOCAL_PATCH:-"$repo_root/configs/u-boot/0021-sync-linux-top-phy-pll-autocal.patch"}
hdmi_top_phy_diag_patch=${HDMI_TOP_PHY_DIAG_PATCH:-"$repo_root/configs/u-boot/0022-add-top-phy-pll-env-diag.patch"}
hdmi_passive_top_phy_diag_patch=${HDMI_PASSIVE_TOP_PHY_DIAG_PATCH:-"$repo_root/configs/u-boot/0028-add-passive-top-phy-env-diag.patch"}
hdmi_mc_clock_patch=${HDMI_MC_CLOCK_PATCH:-"$repo_root/configs/u-boot/0023-sync-linux-hdmi-mc-clock-enable.patch"}
hdmi_tcon_format_patch=${HDMI_TCON_FORMAT_PATCH:-"$repo_root/configs/u-boot/0024-pass-hdmi-format-to-tcon-reinit.patch"}
hdmi_normal_tcon_format_patch=${HDMI_NORMAL_TCON_FORMAT_PATCH:-"$repo_root/configs/u-boot/0027-pass-hdmi-format-to-normal-tcon-init.patch"}
force_cyberdeck_hdmi_mode_patch=${FORCE_CYBERDECK_HDMI_MODE_PATCH:-"$repo_root/configs/u-boot/0025-force-cyberdeck-hdmi-mode.patch"}
hdmi_tv_clock_fallback_patch=${HDMI_TV_CLOCK_FALLBACK_PATCH:-"$repo_root/configs/u-boot/0026-program-hdmi-tv-clock-fallback.patch"}
hdmi_stale_enable_retry_patch=${HDMI_STALE_ENABLE_RETRY_PATCH:-"$repo_root/configs/u-boot/0029-retry-stale-hdmi-enable-state.patch"}
hdmi_logo_recover_patch=${HDMI_LOGO_RECOVER_PATCH:-"$repo_root/configs/u-boot/0030-recover-stale-hdmi-before-logo.patch"}
hdmi_post_logo_retry_patch=${HDMI_POST_LOGO_RETRY_PATCH:-"$repo_root/configs/u-boot/0031-retry-unlocked-hdmi-after-logo-enable.patch"}
hdmi_relaxed_logo_retry_patch=${HDMI_RELAXED_LOGO_RETRY_PATCH:-"$repo_root/configs/u-boot/0032-relax-hdmi-logo-retry-and-report-skip.patch"}
bootgui_hpd_delay_patch=${BOOTGUI_HPD_DELAY_PATCH:-"$repo_root/configs/u-boot/0033-delay-sunxi-show-logo-for-hdmi-hpd.patch"}
early_display_delay_patch=${EARLY_DISPLAY_DELAY_PATCH:-"$repo_root/configs/u-boot/0034-delay-before-sunxi-display-init.patch"}
hdmi_stale_flag_clear_patch=${HDMI_STALE_FLAG_CLEAR_PATCH:-"$repo_root/configs/u-boot/0035-clear-stale-hdmi-drv-enable.patch"}
hdmi_second_pass_patch=${HDMI_SECOND_PASS_PATCH:-"$repo_root/configs/u-boot/0036-hdmi-enable-second-pass-if-unlocked.patch"}
hdmi_second_pass_diag_patch=${HDMI_SECOND_PASS_DIAG_PATCH:-"$repo_root/configs/u-boot/0037-export-hdmi-enable-secondpass-diag.patch"}
hdmi_snps_phy_diag_patch=${HDMI_SNPS_PHY_DIAG_PATCH:-"$repo_root/configs/u-boot/0038-export-snps-phy-config-diag.patch"}
hdmi_no_sw_init_guard_patch=${HDMI_NO_SW_INIT_GUARD_PATCH:-"$repo_root/configs/u-boot/0039-read-hdmi-registers-without-sw-init.patch"}
hdmi_force_second_pass_patch=${HDMI_FORCE_SECOND_PASS_PATCH:-"$repo_root/configs/u-boot/0040-force-hdmi-second-pass-from-env.patch"}
hdmi_force_early_logo_second_pass_patch=${HDMI_FORCE_EARLY_LOGO_SECOND_PASS_PATCH:-"$repo_root/configs/u-boot/0041-force-early-logo-hdmi-second-pass.patch"}
hdmi_preserve_second_pass_mode_set_patch=${HDMI_PRESERVE_SECOND_PASS_MODE_SET_PATCH:-"$repo_root/configs/u-boot/0042-preserve-hdmi-mode-set-after-second-pass.patch"}
hdmi_normalize_disp_info_patch=${HDMI_NORMALIZE_DISP_INFO_PATCH:-"$repo_root/configs/u-boot/0043-normalize-hdmi-disp-info.patch"}
apply_drm_reinit_patch=${APPLY_DRM_REINIT_PATCH:-false}
applied_display_mode_patch=false
selector_logo_generator=${SELECTOR_LOGO_GENERATOR:-"$repo_root/scripts/generate-uboot-selector-logo.py"}
fix_uboot_header=${FIX_UBOOT_HEADER:-"$repo_root/scripts/fix-sunxi-uboot-header.py"}
cross_compile=${CROSS_COMPILE:-arm-linux-gnueabi-}
jobs=${JOBS:-$(nproc)}
defconfig=${DEFCONFIG:-sun60iw2p1_t736_defconfig}

usage() {
  cat <<'USAGE'
Build the Orange Pi vendor U-Boot tree for sun60iw2 without flashing anything.

Usage: scripts/build-vendor-uboot.sh [--baseline|--bootmenu|--scriptfirst-logo|--scriptfirst-diag|--scriptfirst-diag-modeclock|--bootgui-scriptfirst|--bootgui-hpd-delay|--logo-delay-diag|--early-display-delay|--early-display-clockdiag|--early-display-linuxseq|--early-display-enablefix|--early-display-secondpass] [--selector-logo] [--clean]

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
  BOOTGUI_FRAGMENT Kconfig fragment for vendor BOOT_GUI display testing.
  APPLY_DRM_REINIT_PATCH
                   Apply the unsafe 0017 full DRM reinit diagnostic. Default:
                   false. Requires explicit opt-in because one package using
                   this path failed to boot and required external recovery.
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
    --scriptfirst-logo)
      mode=scriptfirst-logo
      selector_logo=true
      ;;
    --scriptfirst-diag)
      mode=scriptfirst-diag
      ;;
    --scriptfirst-diag-modeclock)
      mode=scriptfirst-diag-modeclock
      ;;
    --bootgui-scriptfirst)
      mode=bootgui-scriptfirst
      ;;
    --bootgui-hpd-delay)
      mode=bootgui-hpd-delay
      ;;
    --logo-delay-diag)
      mode=logo-delay-diag
      ;;
    --early-display-delay)
      mode=early-display-delay
      ;;
    --early-display-clockdiag)
      mode=early-display-clockdiag
      ;;
    --early-display-linuxseq)
      mode=early-display-linuxseq
      ;;
    --early-display-enablefix)
      mode=early-display-enablefix
      ;;
    --early-display-secondpass)
      mode=early-display-secondpass
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
require_cmd python3
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

if [ "$mode" = bootmenu ] || [ "$mode" = scriptfirst-logo ] || [ "$mode" = scriptfirst-diag ] || [ "$mode" = scriptfirst-diag-modeclock ] || [ "$mode" = bootgui-scriptfirst ] || [ "$mode" = bootgui-hpd-delay ] || [ "$mode" = logo-delay-diag ] || [ "$mode" = early-display-delay ] || [ "$mode" = early-display-clockdiag ] || [ "$mode" = early-display-linuxseq ] || [ "$mode" = early-display-enablefix ] || [ "$mode" = early-display-secondpass ]; then
  if [ ! -r "$bootmenu_patch" ]; then
    printf 'ERROR: bootmenu source patch not readable: %s\n' "$bootmenu_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply "$bootmenu_patch"
fi

if [ "$mode" = scriptfirst-diag ] || [ "$mode" = scriptfirst-diag-modeclock ]; then
  if [ ! -r "$display_diag_patch" ]; then
    printf 'ERROR: display diagnostic patch not readable: %s\n' "$display_diag_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$display_diag_patch"
  if [ ! -r "$hdmi_diag_patch" ]; then
    printf 'ERROR: HDMI diagnostic patch not readable: %s\n' "$hdmi_diag_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_diag_patch"
  if [ "$mode" = scriptfirst-diag-modeclock ]; then
    for patch in \
      "$hdmi_top_phy_autocal_patch" \
      "$hdmi_mc_clock_patch" \
      "$hdmi_normal_tcon_format_patch"; do
      if [ ! -r "$patch" ]; then
        printf 'ERROR: HDMI Linux-parity patch not readable: %s\n' "$patch" >&2
        exit 1
      fi
      git -C "$work_dir" apply --recount "$patch"
    done
    grep -q 'Match Linux sun60iw2' \
      "$work_dir/drivers/video/drm/sunxi_device/hardware/lowlevel_hdmi20/dw_mc.c" \
      || {
        printf 'ERROR: HDMI MC clock patch did not apply cleanly\n' >&2
        exit 1
      }
    grep -q 'disp_cfg.format = hdmi->disp_config.format' \
      "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
      || {
        printf 'ERROR: HDMI normal TCON format patch did not apply cleanly\n' >&2
        exit 1
      }
    if [ ! -r "$display_mode_patch" ]; then
      printf 'ERROR: display mode patch not readable: %s\n' "$display_mode_patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply "$display_mode_patch"
    applied_display_mode_patch=true
    if [ ! -r "$force_cyberdeck_hdmi_mode_patch" ]; then
      printf 'ERROR: force cyberdeck HDMI mode patch not readable: %s\n' "$force_cyberdeck_hdmi_mode_patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$force_cyberdeck_hdmi_mode_patch"
    grep -q 'drm hdmi force cyberdeck mode' \
      "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
      || {
        printf 'ERROR: force cyberdeck HDMI mode patch did not apply cleanly\n' >&2
        exit 1
      }
    if [ ! -r "$hdmi_mode_clock_patch" ]; then
      printf 'ERROR: HDMI mode clock patch not readable: %s\n' "$hdmi_mode_clock_patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$hdmi_mode_clock_patch"
    grep -q 'mode_rate && (clk_rate == 0 || clk_rate == 24000000)' \
      "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
      || {
        printf 'ERROR: HDMI mode clock patch did not apply cleanly\n' >&2
        exit 1
      }
    if [ ! -r "$hdmi_tv_clock_fallback_patch" ]; then
      printf 'ERROR: HDMI TV clock fallback patch not readable: %s\n' "$hdmi_tv_clock_fallback_patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$hdmi_tv_clock_fallback_patch"
    grep -q 'opi_hdmi_tv_clk' \
      "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
      || {
        printf 'ERROR: HDMI TV clock fallback patch did not apply cleanly\n' >&2
        exit 1
      }
    if [ ! -r "$hdmi_stale_enable_retry_patch" ]; then
      printf 'ERROR: HDMI stale-enable retry patch not readable: %s\n' "$hdmi_stale_enable_retry_patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$hdmi_stale_enable_retry_patch"
    grep -q 'hdmi drv stale enable state' \
      "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
      || {
        printf 'ERROR: HDMI stale-enable retry patch did not apply cleanly\n' >&2
        exit 1
      }
    if [ ! -r "$hdmi_logo_recover_patch" ]; then
      printf 'ERROR: HDMI logo recovery patch not readable: %s\n' "$hdmi_logo_recover_patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$hdmi_logo_recover_patch"
    grep -q 'stale HDMI before logo' \
      "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
      || {
        printf 'ERROR: HDMI logo recovery patch did not apply cleanly\n' >&2
        exit 1
      }
    if [ ! -r "$hdmi_post_logo_retry_patch" ]; then
      printf 'ERROR: HDMI post-logo retry patch not readable: %s\n' "$hdmi_post_logo_retry_patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$hdmi_post_logo_retry_patch"
    grep -q 'HDMI still unlocked after logo enable' \
      "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
      || {
        printf 'ERROR: HDMI post-logo retry patch did not apply cleanly\n' >&2
        exit 1
      }
    if [ ! -r "$hdmi_relaxed_logo_retry_patch" ]; then
      printf 'ERROR: HDMI relaxed logo retry patch not readable: %s\n' "$hdmi_relaxed_logo_retry_patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$hdmi_relaxed_logo_retry_patch"
    grep -q 'post-skip-locked' \
      "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
      || {
        printf 'ERROR: HDMI relaxed logo retry patch did not apply cleanly\n' >&2
        exit 1
      }
    if [ ! -r "$hdmi_passive_top_phy_diag_patch" ]; then
      printf 'ERROR: passive TOP PHY diagnostics patch not readable: %s\n' "$hdmi_passive_top_phy_diag_patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$hdmi_passive_top_phy_diag_patch"
    grep -q 'top20_' \
      "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
      || {
        printf 'ERROR: passive TOP PHY diagnostics patch did not apply cleanly\n' >&2
        exit 1
      }
  fi
  grep -q 'sunxi_hdmi_env' \
    "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
    || {
      printf 'ERROR: HDMI diagnostic patch did not apply cleanly\n' >&2
      exit 1
    }
  grep -q 'sunxi_drm_env' \
    "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
    || {
      printf 'ERROR: DRM diagnostic patch did not apply cleanly\n' >&2
      exit 1
    }
  make "${make_common[@]}" olddefconfig
fi

if [ "$mode" = early-display-clockdiag ]; then
  for patch in \
    "$display_diag_patch" \
    "$hdmi_diag_patch" \
    "$display_mode_patch" \
    "$hdmi_mode_clock_patch" \
    "$hdmi_bus_clock_patch" \
    "$hdmi_tv_clock_fallback_patch" \
    "$hdmi_passive_top_phy_diag_patch" \
    "$early_display_delay_patch"; do
    if [ ! -r "$patch" ]; then
      printf 'ERROR: early-display-clockdiag patch not readable: %s\n' "$patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$patch"
  done
  for marker in \
    sunxi_drm_env \
    sunxi_hdmi_env \
    '1024x600' \
    'mode_rate && (clk_rate == 0 || clk_rate == 24000000)' \
    'hdmi drv bus clock enable' \
    opi_hdmi_tv_clk \
    top20_ \
    'mdelay(8000)'; do
    if ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
      && ! grep -q "$marker" "$work_dir/board/sunxi/board_common.c"; then
      printf 'ERROR: early-display-clockdiag marker missing: %s\n' "$marker" >&2
      exit 1
    fi
  done
  make "${make_common[@]}" olddefconfig
fi

if [ "$mode" = early-display-linuxseq ]; then
  for patch in \
    "$display_diag_patch" \
    "$hdmi_diag_patch" \
    "$display_mode_patch" \
    "$hdmi_mode_clock_patch" \
    "$hdmi_bus_clock_patch" \
    "$hdmi_tv_clock_fallback_patch" \
    "$tcon_hdmi_clock_sequence_patch" \
    "$hdmi_top_phy_autocal_patch" \
    "$hdmi_mc_clock_patch" \
    "$hdmi_normal_tcon_format_patch" \
    "$hdmi_passive_top_phy_diag_patch" \
    "$early_display_delay_patch"; do
    if [ ! -r "$patch" ]; then
      printf 'ERROR: early-display-linuxseq patch not readable: %s\n' "$patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$patch"
  done
  for marker in \
    sunxi_drm_env \
    sunxi_hdmi_env \
    '1024x600' \
    'mode_rate && (clk_rate == 0 || clk_rate == 24000000)' \
    'hdmi drv bus clock enable' \
    opi_hdmi_tv_clk \
    'sun60iw2 HDMI path fully drops the TCON' \
    '_top_phy_pll_auto_cal' \
    'Match Linux sun60iw2' \
    'disp_cfg.format = hdmi->disp_config.format' \
    top20_ \
    'mdelay(8000)'; do
    if ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_device/sunxi_tcon.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_device/hardware/lowlevel_hdmi20/phy_top.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_device/hardware/lowlevel_hdmi20/dw_mc.c" \
      && ! grep -q "$marker" "$work_dir/board/sunxi/board_common.c"; then
      printf 'ERROR: early-display-linuxseq marker missing: %s\n' "$marker" >&2
      exit 1
    fi
  done
  make "${make_common[@]}" olddefconfig
fi

if [ "$mode" = early-display-enablefix ]; then
  for patch in \
    "$display_diag_patch" \
    "$hdmi_diag_patch" \
    "$display_mode_patch" \
    "$hdmi_mode_clock_patch" \
    "$hdmi_bus_clock_patch" \
    "$hdmi_tv_clock_fallback_patch" \
    "$tcon_hdmi_clock_sequence_patch" \
    "$hdmi_top_phy_autocal_patch" \
    "$hdmi_mc_clock_patch" \
    "$hdmi_normal_tcon_format_patch" \
    "$hdmi_passive_top_phy_diag_patch" \
    "$hdmi_stale_flag_clear_patch" \
    "$early_display_delay_patch"; do
    if [ ! -r "$patch" ]; then
      printf 'ERROR: early-display-enablefix patch not readable: %s\n' "$patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$patch"
  done
  for marker in \
    sunxi_drm_env \
    sunxi_hdmi_env \
    '1024x600' \
    'mode_rate && (clk_rate == 0 || clk_rate == 24000000)' \
    'hdmi drv bus clock enable' \
    opi_hdmi_tv_clk \
    'sun60iw2 HDMI path fully drops the TCON' \
    '_top_phy_pll_auto_cal' \
    'Match Linux sun60iw2' \
    'disp_cfg.format = hdmi->disp_config.format' \
    'hdmi drv stale flag reset' \
    top20_ \
    'mdelay(8000)'; do
    if ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_device/sunxi_tcon.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_device/hardware/lowlevel_hdmi20/phy_top.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_device/hardware/lowlevel_hdmi20/dw_mc.c" \
      && ! grep -q "$marker" "$work_dir/board/sunxi/board_common.c"; then
      printf 'ERROR: early-display-enablefix marker missing: %s\n' "$marker" >&2
      exit 1
    fi
  done
  make "${make_common[@]}" olddefconfig
fi

if [ "$mode" = early-display-secondpass ]; then
  for patch in \
    "$display_diag_patch" \
    "$hdmi_diag_patch" \
    "$display_fbtest_patch" \
    "$display_mode_patch" \
    "$hdmi_mode_clock_patch" \
    "$hdmi_bus_clock_patch" \
    "$hdmi_pattern_status_patch" \
    "$hdmi_pattern_reconfig_patch" \
    "$hdmi_tv_clock_fallback_patch" \
    "$tcon_hdmi_clock_sequence_patch" \
    "$hdmi_top_phy_autocal_patch" \
    "$hdmi_mc_clock_patch" \
    "$hdmi_normal_tcon_format_patch" \
    "$hdmi_passive_top_phy_diag_patch" \
    "$hdmi_stale_flag_clear_patch" \
    "$hdmi_second_pass_patch" \
    "$hdmi_second_pass_diag_patch" \
    "$hdmi_snps_phy_diag_patch" \
    "$hdmi_no_sw_init_guard_patch" \
    "$hdmi_force_second_pass_patch" \
    "$hdmi_force_early_logo_second_pass_patch" \
    "$hdmi_preserve_second_pass_mode_set_patch" \
    "$hdmi_normalize_disp_info_patch" \
    "$early_display_delay_patch"; do
    if [ ! -r "$patch" ]; then
      printf 'ERROR: early-display-secondpass patch not readable: %s\n' "$patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$patch"
  done
  for marker in \
    sunxi_drm_env \
    sunxi_hdmi_env \
    'sunxi_drm fbtest' \
    '1024x600' \
    'mode_rate && (clk_rate == 0 || clk_rate == 24000000)' \
    'hdmi drv bus clock enable' \
    opi_hdmi_pattern_diag \
    opi_hdmi_pattern_reconfig \
    opi_hdmi_tv_clk \
    'sun60iw2 HDMI path fully drops the TCON' \
    '_top_phy_pll_auto_cal' \
    'Match Linux sun60iw2' \
    'disp_cfg.format = hdmi->disp_config.format' \
    'hdmi drv stale flag reset' \
    'hdmi %s second pass' \
    'second-pass driver disable' \
    opi_hdmi_secondpass \
    opi_hdmi_drv_diag \
    opi_snps_phy_diag \
    opi_hdmi_force_secondpass \
    'hdmisp=%s' \
    'env_set("opi_hdmi_force_secondpass", "1")' \
    'hdmi->hdmi_ctrl.drm_mode_set = 0x1' \
    'hdmi aspect info normalized for early boot' \
    'HDMI_ACTIVE_ASPECT_PICTURE' \
    'if (dw) {' \
    top20_ \
    'mdelay(8000)'; do
    if ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_device/sunxi_tcon.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_device/hardware/lowlevel_hdmi20/phy_top.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_device/hardware/lowlevel_hdmi20/phy_snps.c" \
      && ! grep -q "$marker" "$work_dir/drivers/video/drm/sunxi_device/hardware/lowlevel_hdmi20/dw_mc.c" \
      && ! grep -q "$marker" "$work_dir/board/sunxi/board_common.c"; then
      printf 'ERROR: early-display-secondpass marker missing: %s\n' "$marker" >&2
      exit 1
    fi
  done
  make "${make_common[@]}" olddefconfig
fi

if [ "$mode" = early-display-delay ]; then
  for patch in \
    "$display_diag_patch" \
    "$hdmi_diag_patch" \
    "$early_display_delay_patch"; do
    if [ ! -r "$patch" ]; then
      printf 'ERROR: early-display-delay patch not readable: %s\n' "$patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$patch"
  done
  grep -q 'sunxi_drm_env' \
    "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
    || {
      printf 'ERROR: DRM env diagnostic patch did not apply cleanly\n' >&2
      exit 1
    }
  grep -q 'sunxi_hdmi_env' \
    "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
    || {
      printf 'ERROR: HDMI env diagnostic patch did not apply cleanly\n' >&2
      exit 1
    }
  if ! grep -q 'initr_sunxi_display' "$work_dir/board/sunxi/board_common.c" \
    || ! grep -q 'mdelay(8000)' "$work_dir/board/sunxi/board_common.c"; then
    printf 'ERROR: early display delay patch did not apply cleanly\n' >&2
    exit 1
  fi
  make "${make_common[@]}" olddefconfig
fi

if [ "$mode" = logo-delay-diag ]; then
  for patch in \
    "$display_diag_patch" \
    "$hdmi_diag_patch" \
    "$bootgui_hpd_delay_patch"; do
    if [ ! -r "$patch" ]; then
      printf 'ERROR: logo-delay diagnostic patch not readable: %s\n' "$patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$patch"
  done
  grep -q 'sunxi_drm_env' \
    "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
    || {
      printf 'ERROR: DRM env diagnostic patch did not apply cleanly\n' >&2
      exit 1
    }
  grep -q 'sunxi_hdmi_env' \
    "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
    || {
      printf 'ERROR: HDMI env diagnostic patch did not apply cleanly\n' >&2
      exit 1
    }
  grep -q 'waiting 5 seconds before sunxi_show_logo' \
    "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
    || {
      printf 'ERROR: sunxi_show_logo HPD delay patch did not apply cleanly\n' >&2
      exit 1
    }
  make "${make_common[@]}" olddefconfig
fi

if [ "$mode" = bootmenu ]; then
  if [ ! -r "$display_diag_patch" ]; then
    printf 'ERROR: display diagnostic patch not readable: %s\n' "$display_diag_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$display_diag_patch"
  if [ "$apply_display_mode_patch" = true ]; then
    if [ ! -r "$display_mode_patch" ]; then
      printf 'ERROR: display mode patch not readable: %s\n' "$display_mode_patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply "$display_mode_patch"
    applied_display_mode_patch=true
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
  git -C "$work_dir" apply --recount "$bootgui_selector_patch"
  if [ ! -r "$bootgui_selector_all_displays_patch" ]; then
    printf 'ERROR: boot GUI all-displays patch not readable: %s\n' "$bootgui_selector_all_displays_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$bootgui_selector_all_displays_patch"
  if [ ! -r "$a733_logo_loader_patch" ]; then
    printf 'ERROR: A733 logo loader patch not readable: %s\n' "$a733_logo_loader_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$a733_logo_loader_patch"
  if [ ! -r "$high_contrast_selector_patch" ]; then
    printf 'ERROR: high-contrast selector patch not readable: %s\n' "$high_contrast_selector_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$high_contrast_selector_patch"
  if [ ! -r "$hdmi_diag_patch" ]; then
    printf 'ERROR: HDMI diagnostic patch not readable: %s\n' "$hdmi_diag_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_diag_patch"
  if [ ! -r "$hdmi_mode_clock_patch" ]; then
    printf 'ERROR: HDMI mode clock patch not readable: %s\n' "$hdmi_mode_clock_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_mode_clock_patch"
  if [ ! -r "$hdmi_bus_clock_patch" ]; then
    printf 'ERROR: HDMI bus clock patch not readable: %s\n' "$hdmi_bus_clock_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_bus_clock_patch"
  if [ ! -r "$hdmi_pattern_status_patch" ]; then
    printf 'ERROR: HDMI pattern status patch not readable: %s\n' "$hdmi_pattern_status_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_pattern_status_patch"
  if [ ! -r "$hdmi_top_phy_pddq_patch" ]; then
    printf 'ERROR: HDMI top-PHY PDDQ patch not readable: %s\n' "$hdmi_top_phy_pddq_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_top_phy_pddq_patch"
  grep -q 'phy_pddq[[:space:]]*=[[:space:]]*0x0;' \
    "$work_dir/drivers/video/drm/sunxi_device/hardware/lowlevel_hdmi20/phy_top.c" \
    || {
      printf 'ERROR: top-PHY PDDQ patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$hdmi_pattern_reconfig_patch" ]; then
    printf 'ERROR: HDMI pattern reconfig patch not readable: %s\n' "$hdmi_pattern_reconfig_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_pattern_reconfig_patch"
  grep -q 'opi_hdmi_pattern_reconfig' \
    "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
    || {
      printf 'ERROR: HDMI pattern reconfig patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$hdmi_pattern_full_reinit_patch" ]; then
    printf 'ERROR: HDMI pattern full-reinit patch not readable: %s\n' "$hdmi_pattern_full_reinit_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_pattern_full_reinit_patch"
  grep -q '_sunxi_hdmi_reinit_active_display' \
    "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
    || {
      printf 'ERROR: HDMI pattern full-reinit patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$hdmi_reinit_stage_diag_patch" ]; then
    printf 'ERROR: HDMI reinit stage diagnostics patch not readable: %s\n' "$hdmi_reinit_stage_diag_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_reinit_stage_diag_patch"
  grep -q 'opi_hdmi_reinit_diag' \
    "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
    || {
      printf 'ERROR: HDMI reinit stage diagnostics patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$tcon_hdmi_clock_sequence_patch" ]; then
    printf 'ERROR: HDMI TCON clock sequence patch not readable: %s\n' "$tcon_hdmi_clock_sequence_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$tcon_hdmi_clock_sequence_patch"
  grep -q 'Linux.s sun60iw2 HDMI path fully drops the TCON' \
    "$work_dir/drivers/video/drm/sunxi_device/sunxi_tcon.c" \
    || {
      printf 'ERROR: HDMI TCON clock sequence patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$hdmi_fc_iteration_patch" ]; then
    printf 'ERROR: HDMI frame-composer iteration patch not readable: %s\n' "$hdmi_fc_iteration_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_fc_iteration_patch"
  grep -q 'dw_fc_iteration_process();' \
    "$work_dir/drivers/video/drm/sunxi_device/hardware/lowlevel_hdmi20/dw_avp.c" \
    || {
      printf 'ERROR: HDMI frame-composer iteration patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$hdmi_phy_rxsense_patch" ]; then
    printf 'ERROR: HDMI PHY RX-sense patch not readable: %s\n' "$hdmi_phy_rxsense_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_phy_rxsense_patch"
  grep -q 'dw_phy_wait_rxsense' \
    "$work_dir/drivers/video/drm/sunxi_device/hardware/lowlevel_hdmi20/phy_snps.c" \
    || {
      printf 'ERROR: HDMI PHY RX-sense patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$hdmi_top_phy_autocal_patch" ]; then
    printf 'ERROR: HDMI TOP PHY autocal patch not readable: %s\n' "$hdmi_top_phy_autocal_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_top_phy_autocal_patch"
  grep -q '_top_phy_pll_auto_cal' \
    "$work_dir/drivers/video/drm/sunxi_device/hardware/lowlevel_hdmi20/phy_top.c" \
    || {
      printf 'ERROR: HDMI TOP PHY autocal patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$hdmi_top_phy_diag_patch" ]; then
    printf 'ERROR: HDMI TOP PHY diagnostics patch not readable: %s\n' "$hdmi_top_phy_diag_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_top_phy_diag_patch"
  grep -q 'top20_' \
    "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
    || {
      printf 'ERROR: HDMI TOP PHY diagnostics patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$hdmi_mc_clock_patch" ]; then
    printf 'ERROR: HDMI MC clock patch not readable: %s\n' "$hdmi_mc_clock_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_mc_clock_patch"
  grep -q 'let the audio clock settle' \
    "$work_dir/drivers/video/drm/sunxi_device/hardware/lowlevel_hdmi20/dw_mc.c" \
    || {
      printf 'ERROR: HDMI MC clock patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$hdmi_tcon_format_patch" ]; then
    printf 'ERROR: HDMI TCON format patch not readable: %s\n' "$hdmi_tcon_format_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_tcon_format_patch"
  grep -q 'disp_cfg.format = hdmi->disp_config.format;' \
    "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
    || {
      printf 'ERROR: HDMI TCON format patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$hdmi_stale_enable_retry_patch" ]; then
    printf 'ERROR: HDMI stale-enable retry patch not readable: %s\n' "$hdmi_stale_enable_retry_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_stale_enable_retry_patch"
  grep -q 'PHY_STAT0_RX_SENSE_ALL_MASK' \
    "$work_dir/drivers/video/drm/sunxi_drm_hdmi.c" \
    || {
      printf 'ERROR: HDMI stale-enable retry patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$hdmi_logo_recover_patch" ]; then
    printf 'ERROR: HDMI logo recovery patch not readable: %s\n' "$hdmi_logo_recover_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_logo_recover_patch"
  grep -q 'stale HDMI before logo' \
    "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
    || {
      printf 'ERROR: HDMI logo recovery patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$hdmi_post_logo_retry_patch" ]; then
    printf 'ERROR: HDMI post-logo retry patch not readable: %s\n' "$hdmi_post_logo_retry_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_post_logo_retry_patch"
  grep -q 'HDMI still unlocked after logo enable' \
    "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
    || {
      printf 'ERROR: HDMI post-logo retry patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ ! -r "$hdmi_relaxed_logo_retry_patch" ]; then
    printf 'ERROR: HDMI relaxed logo retry patch not readable: %s\n' "$hdmi_relaxed_logo_retry_patch" >&2
    exit 1
  fi
  git -C "$work_dir" apply --recount "$hdmi_relaxed_logo_retry_patch"
  grep -q 'post-skip-locked-rxsense' \
    "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
    || {
      printf 'ERROR: HDMI relaxed logo retry patch did not apply cleanly\n' >&2
      exit 1
    }
  if [ "$apply_drm_reinit_patch" = true ]; then
    if [ ! -r "$drm_reinit_visual_diag_patch" ]; then
      printf 'ERROR: DRM reinit visual diagnostics patch not readable: %s\n' "$drm_reinit_visual_diag_patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$drm_reinit_visual_diag_patch"
    grep -q 'sunxi_drm_reinit_active' \
      "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
      || {
        printf 'ERROR: DRM reinit visual diagnostics patch did not apply cleanly\n' >&2
        exit 1
      }
  fi
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

if [ "$mode" = bootgui-scriptfirst ] || [ "$mode" = bootgui-hpd-delay ]; then
  if [ "$mode" = bootgui-hpd-delay ]; then
    if [ ! -r "$bootgui_hpd_delay_patch" ]; then
      printf 'ERROR: BootGUI HPD delay patch not readable: %s\n' "$bootgui_hpd_delay_patch" >&2
      exit 1
    fi
    git -C "$work_dir" apply --recount "$bootgui_hpd_delay_patch"
    grep -q 'waiting 5 seconds before sunxi_show_logo' \
      "$work_dir/drivers/video/drm/sunxi_drm_drv.c" \
      || {
        printf 'ERROR: sunxi_show_logo HPD delay patch did not apply cleanly\n' >&2
        exit 1
      }
  fi
  if [ ! -r "$fragment" ]; then
    printf 'ERROR: config fragment not readable: %s\n' "$fragment" >&2
    exit 1
  fi
  bootgui_mode_fragment=$bootgui_fragment
  if [ "$mode" = bootgui-hpd-delay ]; then
    bootgui_mode_fragment=$awdrm_bootgui_fragment
  fi
  if [ ! -r "$bootgui_mode_fragment" ]; then
    printf 'ERROR: BOOT_GUI config fragment not readable: %s\n' "$bootgui_mode_fragment" >&2
    exit 1
  fi
  (
    cd "$work_dir"
    CROSS_COMPILE="$cross_compile" ./scripts/kconfig/merge_config.sh .config "$fragment" "$bootgui_mode_fragment"
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

for uboot_image in \
  "$work_dir/u-boot.bin" \
  "$work_dir/u-boot-dtb.bin" \
  "$work_dir/u-boot-sun60iw2p1.bin" \
  "$artifact_dir/lichee-chip/orangepi4pro/bin/u-boot-sun60iw2p1.bin" \
  "$artifact_dir/lichee-plat/u-boot-sun60iw2p1.bin"; do
  if [ -e "$uboot_image" ]; then
    python3 "$fix_uboot_header" "$uboot_image"
  fi
done

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

grep -E 'CONFIG_(CMD_BOOTMENU|AUTOBOOT_MENU_SHOW|USB_KEYBOARD|SYS_USB_EVENT_POLL|DM_KEYBOARD|EFI_LOADER|BOOTDELAY|DISP2_SUNXI|HDMI2_DISP2_SUNXI|DEFAULT_PHY|BOOT_GUI|UPDATE_DISPLAY_MODE|CMD_SUNXI_BMP|SUNXI_DRM_SUPPORT|DM_VIDEO|AW_DRM)=' \
  "$work_dir/.config" > "$artifact_dir/$artifact_mode/config-summary.txt" || true

cat > "$artifact_dir/$artifact_mode/SOURCE.txt" <<EOF
url=$source_url
branch=$source_branch
commit=$source_commit
defconfig=$defconfig
mode=$mode
selector_logo=$selector_logo
apply_display_mode_patch=$apply_display_mode_patch
applied_display_mode_patch=$applied_display_mode_patch
apply_drm_reinit_patch=$apply_drm_reinit_patch
bootgui_fragment=$bootgui_fragment
awdrm_bootgui_fragment=$awdrm_bootgui_fragment
cross_compile=$cross_compile
dtc=${DTC:-/usr/bin/dtc}
EOF

printf 'Built vendor U-Boot artifacts in %s/%s\n' "$artifact_dir" "$artifact_mode"
printf 'No install or flash action was performed.\n'
