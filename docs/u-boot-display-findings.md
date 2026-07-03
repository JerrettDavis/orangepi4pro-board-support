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

Current candidate:

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
