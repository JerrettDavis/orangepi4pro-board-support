# U-Boot Display Findings

Captured 2026-07-02 after the video-first selector test hung before Linux.

Known-good control-flow result:

- A script-first U-Boot package did run `/boot/boot.scr` before extlinux.
- The boot script entered `bootmenu`.
- With no visible selector, it still selected the NVMe default after timeout.
- Linux then showed `bootchooser=uboot-bootmenu-nvme`.

Known-bad display result:

- Forcing `stdout=vidconsole,serial` and calling `sunxi_show_bmp boot.bmp` from
  `boot.scr` hung the boot on this board.
- The machine was recovered externally by restoring safe SD boot files and an
  extlinux-first SD U-Boot package.

Relevant vendor-source findings:

- `cmd/bootmenu.c` renders with ANSI text through normal U-Boot stdio using
  `puts()` and `printf()`. If the `vidconsole` backend is not visible on the
  panel, `bootmenu` is also not visible.
- `drivers/video/drm/sunxi_drm_drv.c` implements `sunxi_show_bmp()` by loading
  a logo and calling `display_logo()`, which can re-enable or reconfigure the
  DRM display.
- `drivers/video/drm/load_file.c` rewrites the requested filename to
  `/boot/boot.bmp`, scans hardcoded devices, and can fall back to an embedded
  gzip BMP array. It is not a safe generic draw command for a boot script.
- `board/sunxi/board_common.c` has a separate early-logo path driven by
  `gd->boot_logo_addr` and boot-package logo data.

Implication:

The U-Boot selector is functionally usable, but the deck display path is not
yet a reliable U-Boot console. The next safe visual selector design should stay
inside the vendor early-logo path or use a small U-Boot-side display patch that
draws directly to the already initialized framebuffer. Do not call
`sunxi_show_bmp` from `boot.scr`.

Earlier candidate:

- `scripts/generate-uboot-selector-logo.py` writes a deterministic replacement
  `drivers/video/drm/boot_bmp.h` before compiling U-Boot.
- `scripts/build-vendor-uboot.sh --selector-logo --clean` builds the
  script-first bootmenu U-Boot with that embedded selector image and the
  `sunxi_drm_env` diagnostic command.
- The generated selector BMP is 320 x 240 x 24-bit and 230454 bytes, so it is
  comfortably below the vendor logo decompression buffer size.
- Linux uses HDMI-A at `1024x600` with a 49.00 MHz pixel clock:
  `1024 1029 1042 1312 600 602 605 622 -hsync +vsync`. The vendor U-Boot
  fallback was `1920x1080` and produced no visible pre-kernel output on the
  cyberdeck panel.
- The installed SD boot-package test candidate is
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu-scriptfirst-selector-logo-drm-env-1024x600.fex`.
- Candidate SHA-256:
  `79034667cf71181c620568607fa085c7eb551a026a208992e2a310bc0d0f1647`.
- U-Boot item SHA-256:
  `ac4c20b765e56427e27cad48e069ebee34ad3ae7f9fbf6b71e67cc747ff2b12e`.
- Recovery backup:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T010829Z.bin`.
- Recovery backup SHA-256:
  `12ba9643679371de85327ca0a4019911a5190cb18def9832b07c30932c20c2cc`.

This candidate is intended to prove whether vendor U-Boot has an active DRM
connector and framebuffer before Linux starts. The paired boot script appends
`opi_pre_*` and `opi_post_*` diagnostics to `/proc/cmdline`; actual text-menu
rendering still depends on whether U-Boot's console backend reaches the panel.

The 1024x600 colorbar reboot still produced a black pre-kernel display even
though U-Boot reported HDMI-A enabled at `1024x600`, 49 MHz, and a 1024x600
framebuffer. The next test bypasses TCON pattern generation and uses
`sunxi_drm fbtest`, which calls the vendor framebuffer/display-enable path and
paints directly into the active DRM framebuffer.

2026-07-03 follow-up:

- The current installed SD TOC1 package is the stock vendor U-Boot with only
  script-first scan order patched:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_vendor-sd-scriptfirst.fex`.
  Readback from `/dev/mmcblk1` at `bs=8192 skip=2050` matches SHA-256
  `77ef94aee8f8a6ec27d130822b70187fbf4316773d7ae5d59150e9027c654670`.
- The SD `boot0_sdcard.fex` region at `bs=8192 skip=1` matches the vendor
  package byte-for-byte. The missing pre-Linux display is not explained by a
  corrupted boot0 or partial TOC1 write.
- The factory-SD-derived script-first vendor package booted Linux through
  `bootchooser=extlinux-legacy-nvme`, but it produced no pre-Linux factory
  splash and no selector.
- The embedded U-Boot DTB in the vendor SD, vendor NVMe, and current
  script-first packages has root compatible strings `allwinner,a733` and
  `arm,sun60iw2p1`; it is not the Linux board DTB with
  `xunlong,orangepi-4-pro`.
- In the embedded U-Boot DTB, `/soc/hdmi0@5520000` sets `hdmi_power0` and
  `hdmi_power1` as strings (`dcdc2-supply`, `dldo2-supply`). The U-Boot helper
  used by `sunxi_drm_hdmi.c` reads these properties as integer phandles via
  `uclass_get_device_by_phandle()`.
- The same U-Boot HDMI driver reads `uhdmi_power_count` and
  `uhdmi_resistor_select`, but the packed vendor DTB uses
  `hdmi_power_cnt` and `hdmi_resistor_select`. As a result the driver can skip
  HDMI regulator setup even when `hdmi_power0/1` are present.
- The Linux DTB that brings the panel up uses `cldo2` for HDMI power1:
  `dcdc2-supply`, `cldo2-supply`, `hdmi_power0 = "dcdc2"`,
  `hdmi_power1 = "cldo2"`. The packed U-Boot DTB has no `cldo2` regulator node
  and uses `dldo2` instead.
- `scripts/prepare-vendor-sd-hdmi-phandle-package.sh` creates a file-only
  package candidate that preserves vendor U-Boot, preserves script-first
  scanning, and rewrites only those two HDMI power properties to phandles
  pointing at the existing `dcdc2-supply` and `dldo2-supply` regulator nodes.
  That candidate is now superseded by the HDMI-power candidate below because it
  made the wrong regulator reference internally consistent.

Current HDMI-power candidate:

- `scripts/prepare-vendor-sd-hdmi-power-package.sh` creates a file-only
  package candidate from stock vendor U-Boot. It preserves the factory embedded
  logo path and script-first scanning, adds the U-Boot-specific
  `uhdmi_power_count`/`uhdmi_resistor_select` properties, creates a `cldo2`
  regulator node matching the working Linux DTB, and points `hdmi_power0/1` at
  regulator phandles.
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_vendor-sd-scriptfirst-hdmi-power.fex`
- Package SHA-256:
  `d4fe6a813c40766b9f00872b46ab3f1b72dfe70910bc1330b346605ffbf89bc7`
- U-Boot item SHA-256:
  `2d183202272a484cf21a79d684cdf5752a32afa061eece481ef9af38bce44731`
- Expected test behavior: the existing `/boot/boot.scr` calls
  `sunxi_show_logo` and holds for 15 seconds before extlinux. If the HDMI power
  mismatch is the blocker, the bootloader window should show an obvious splash
  or logo before the kernel dmesg/Plymouth phase.

2026-07-03 diagnostic package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-diagnostic-fbtest-hdmi-power.fex`
- Package SHA-256:
  `fcfac8e4e89b6b4c5237bc7649064f3a9bf0d3d85a4b64a5eddd47e3b3ec8d81`
- U-Boot item SHA-256:
  `6beece37c94f128b1e45a06bb97f5cf043699e63399ae5bfde74afeac9f4da62`
- Source package:
  `boot_package_sd-bootmenu-scriptfirst-selector-logo-drm-env-1024x600-fbtest.fex`
- This package combines the custom diagnostic U-Boot commands
  (`sunxi_drm_env`, `sunxi_drm fbtest`) with the HDMI power DTB correction
  from `scripts/prepare-vendor-sd-hdmi-power-package.sh`.
- The staged boot script runs `selector_visual_test=fbtest`, holds for 20
  seconds, boots NVMe through the legacy `bootm` path, and appends
  `bootchooser=uboot-visual-fbtest-*` plus `opi_pre_*`, `opi_fb_*`, and
  `opi_post_*` diagnostics to `/proc/cmdline`.
- The first reboot with this package produced
  `bootchooser=uboot-visual-fbtest-ok` and
  `opi_fb_fbtest=ok,w=1024,h=600,addr=b3dfd000,size=2457600`, but the display
  still showed no bootloader image. That proved U-Boot could initialize HDMI-A
  and write the framebuffer memory; it did not prove that the painted
  framebuffer was bound to the active display plane.

2026-07-03 plane-commit diagnostic package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-fbtest-planecommit-hdmi-power.fex`
- Package SHA-256:
  `19f2f5fb2874f9c836963921cf63fa66be652948f2fdbdb87ccf938dd8696c85`
- U-Boot item SHA-256:
  `2b228ee3ce7d9e62b908c1c12b36a5ebd973f7425285a6974f575600fb7a2f06`
- Recovery backup:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T052915Z.bin`
- Recovery backup SHA-256:
  `47dc28d4227b5d0e9ff6234409e750bc95dfe03ba0930a8e21d3c6a3e3ed7dad`
- This package changes `sunxi_drm fbtest` to select the display state, paint
  that state's framebuffer, call `display_set_plane(state)`, flush the CRTC,
  and re-enable backlight. The diagnostic string now includes `fbid`, `plane`,
  and `en` fields, for example `fbid=0,plane=0,en=1` when the primary plane
  commit succeeds.
- The reboot with this package reported
  `opi_fb_fbtest=ok,w=1024,h=600,addr=b3dfe000,size=2457600,fbid=0,plane=0,en=1`.
  That proves the active framebuffer was bound to the primary plane without a
  U-Boot error. If the screen is still black, the remaining suspect is HDMI
  transmitter clock/PHY setup rather than selector rendering.

2026-07-03 HDMI TCON-clock diagnostic package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-fbtest-planecommit-hdmi-power-tconclk.fex`
- Package SHA-256:
  `2a4268c4dc2ce8f5731c87390e555ceeabd12b0f4223739675bbb2bb374154a9`
- U-Boot item SHA-256:
  `78d6733557ffa96952cdbe949268adc427ce8ad287d4049f829e44117b73798b`
- Recovery backup:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T053453Z.bin`
- Recovery backup SHA-256:
  `ef4edba61f9d29244dee447171b2281322bc22f1318f8289d3b7389977168df9`
- The packed U-Boot HDMI node did not expose a `clk_tcon_tv` clock-name even
  though `_sunxi_drv_hdmi_set_rate()` reads it and uses it to set `clk_hdmi`.
  `scripts/prepare-vendor-sd-hdmi-power-package.sh` now prepends the active
  TCON clock to the HDMI node as `clk_tcon_tv`, preserving the existing
  `clk_hdmi`, `clk_hdmi_24M`, `rst_main`, and `rst_sub` entries.

2026-07-03 A733 NVMe HDMI-power stock-display package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-nvme-scriptfirst-hdmi-power.fex`
- Package SHA-256:
  `4bcaf2bfa38c7308f717a6afeeb9a10a50b669dbe3ec7ceff258e469f8c648ae`
- U-Boot item SHA-256:
  `f557839b048b86a7b3dbeb72bf8d9b2e9a1dc6065d86e12ca81b786c938d4ae0`
- Source package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`
- Recovery backup:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T061415Z.bin`
- Recovery backup SHA-256:
  `02ee28b4badbf2a75c7b87279d4178591746e1bb72eeff184b7250e961b2648a`
- This package applies the same HDMI power, CLDO2, and `clk_tcon_tv` DTB
  corrections to the larger Orange Pi A733 NVMe vendor package. It preserves
  the stock `U-Boot 2018.07-orangepi-config-dirty (Nov 21 2025 - 10:05:52
  +0000)` payload and changes only the distro scan order plus embedded DTB.
- The paired boot script stages `selector_logo_preinit=true` and
  `selector_logo_hold=15`, so a successful HDMI fix should show the vendor
  `sunxi_show_logo` output for a long, visible bootloader window before
  extlinux continues.

Installed framebuffer-test package:

- Package SHA-256:
  `831fad7f31e02c3fe099c2e83402ffc207d93ce2fe41272cb26fb8758fe9a2a0`.
- U-Boot item SHA-256:
  `472dd23358166ac1730513bcba60ec8606dba92d8ae87456bde61f851c5a5ae8`.
- Recovery backup:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T011715Z.bin`.
- Recovery backup SHA-256:
  `d44158d530b844a15b7420fa22404ae7a4c1ce8005b42b4c260510dbe4e84f3f`.
