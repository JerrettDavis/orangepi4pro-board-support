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
yet a reliable U-Boot console. The next safe visual selector design should use
either a boot-package early-logo replacement or a small U-Boot-side display
patch that draws directly to the already initialized framebuffer. It should be
tested on a recovery SD first, with serial logs captured, before touching the
primary SD bootloader package again.
