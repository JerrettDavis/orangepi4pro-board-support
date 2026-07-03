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

Installed framebuffer-test package:

- Package SHA-256:
  `831fad7f31e02c3fe099c2e83402ffc207d93ce2fe41272cb26fb8758fe9a2a0`.
- U-Boot item SHA-256:
  `472dd23358166ac1730513bcba60ec8606dba92d8ae87456bde61f851c5a5ae8`.
- Recovery backup:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T011715Z.bin`.
- Recovery backup SHA-256:
  `d44158d530b844a15b7420fa22404ae7a4c1ce8005b42b4c260510dbe4e84f3f`.
