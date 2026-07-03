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

2026-07-03 A733 NVMe HDMI fast-output 1024x600 package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-nvme-scriptfirst-hdmi-power-fast1024.fex`
- Package SHA-256:
  `54790bdb8434451e9f37a05c9f6bf1eda4ce844bbb90f8ee9b99abb33dbde083`
- U-Boot item SHA-256:
  `69c6a93ff7c3ae65c7bf2003a246c269ac41cbbe1185af0f76e1211779a48192`
- Source package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`
- Recovery backup:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T062446Z.bin`
- Recovery backup SHA-256:
  `d0325b8ea7a7c8a4574ac122044f9cd91be0bb8b6462ac6b1085852364d044b4`
- Build command:
  `scripts/prepare-vendor-sd-hdmi-power-package.sh --fast-1024x600 --vendor /usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex --output /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-nvme-scriptfirst-hdmi-power-fast1024.fex`
- This package keeps the A733 HDMI power, CLDO2, and `clk_tcon_tv` DTB fixes,
  sets `uhdmi_fast_output=1`, and patches the first compiled HDMI default mode
  table from `1920x1080` at 148.5 MHz to the Linux-proven `1024x600` timing at
  49.0 MHz. The patched mode uses `1024 1029 1042 1312 600 602 605 622` with
  negative hsync and positive vsync.

2026-07-03 A733 NVMe HDMI fast-output 1024x600 force-route package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-nvme-scriptfirst-hdmi-power-fast1024-force-route.fex`
- Package SHA-256:
  `0bdbae3771f0fe8be50af30af05d8f29a9b39fb0b94db10fd7edd6de99a7d46c`
- U-Boot item SHA-256:
  `a7da32e4ec45c1a934499448a86a8fca1017a98880056f174d2d175045e4997c`
- Source package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`
- Build command:
  `scripts/prepare-vendor-sd-hdmi-power-package.sh --fast-1024x600 --force-route --vendor /usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex --output /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-nvme-scriptfirst-hdmi-power-fast1024-force-route.fex`
- Recovery backup:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T063108Z.bin`
- Recovery backup SHA-256:
  `776469c39bfac3716317d64c0c25d8ce733d576dc2e69311f6088db91e6c0f8e`
- This package adds only one behavior beyond the previous fast-output package:
  `/soc/sunxi-drm/route/disp0_hdmi0` now has a boolean `force-output`
  property. In vendor U-Boot, `display_init()` deinitializes a route when
  detect fails and `force-output` is absent. This test keeps the Linux-proven
  1024x600 fallback timing and forces the HDMI route to stay initialized even
  if early HPD is low.
- Reboot result: Linux still reached `bootchooser=extlinux-legacy-nvme`, but
  no bootloader output was visible before the Orange Pi OS loader/desktop.

2026-07-03 A733 NVMe HDMI fast-output 720p force-route package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-nvme-scriptfirst-hdmi-power-fast720p-force-route.fex`
- Package SHA-256:
  `a2cb9fe115144f8f3509a06d8a5efd3953dc12e622fce6063f7f0b4560adb7ce`
- U-Boot item SHA-256:
  `2dc9b0e71b1fe1c8f0dc4147d6a8c14059a47cc4fd0f40fc90aec527474733da`
- Source package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`
- Build command:
  `scripts/prepare-vendor-sd-hdmi-power-package.sh --hdmi-default-mode 1280x720 --force-route --vendor /usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex --output /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-nvme-scriptfirst-hdmi-power-fast720p-force-route.fex`
- Recovery backup:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T063544Z.bin`
- Recovery backup SHA-256:
  `61e07915eda5d5d538f715199c9a6876a2e360a27f2ef0b66df76fc1c6c9cb8b`
- Rationale: the previous `1024x600` package used a 49.00 MHz pixel clock.
  Vendor U-Boot's sun60i top PHY table does not contain 49 MHz and rounds to
  a nearby standard PLL entry. This package keeps the HDMI power, CLDO2,
  `clk_tcon_tv`, `uhdmi_fast_output=1`, and `force-output` changes, but uses
  the standard `1280x720@60` mode at 74.25 MHz. That exact clock exists in the
  U-Boot top PHY PLL table, and Linux reports `1280x720` as an available mode
  on the live HDMI connector.
- Reboot result: Linux still reached `bootchooser=extlinux-legacy-nvme`, but
  no bootloader output was visible before desktop.

2026-07-03 custom bootmenu HDMI diagnostic 720p force-route package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-diag-fast720p-force-route.fex`
- Package SHA-256:
  `1549376b7ed488e358667dbb5ff7de0df09ee5e3efe41b4922fc2e6bd518d8a9`
- U-Boot item SHA-256:
  `1948c93eb50bd316c331cf98562f6dfdee2436cc26ecd4f07a1ef00b1e97c66c`
- Source package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`
- Build commands:
  `APPLY_DISPLAY_MODE_PATCH=false scripts/build-vendor-uboot.sh --bootmenu --clean`
  `scripts/prepare-vendor-sd-hdmi-power-package.sh --uboot .build/u-boot/artifacts/bootmenu/u-boot-sun60iw2p1.bin --hdmi-default-mode 1280x720 --force-route --vendor /usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex --output /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-diag-fast720p-force-route.fex`
- Recovery backup:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T064907Z.bin`
- Recovery backup SHA-256:
  `0a5e149cfe14a96cf322f90e8b9cc6b6c23a423c852141a79a6973231923f098`
- This package adds `sunxi_hdmi_env`, which exports HDMI HPD, clock, output,
  mode-set, pixel/TMDS clock, and top PHY lock/status data to `opi_hdmi_diag`.
  The boot script appends those diagnostics to the legacy `bootm` kernel
  command line during bounded visual tests. The package still applies the A733
  HDMI power, CLDO2, `clk_tcon_tv`, `uhdmi_fast_output=1`, 720p fallback, and
  force-route changes.

2026-07-03 custom bootmenu HDMI clock-route 720p package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-clockroute-720p.fex`
- Package SHA-256:
  `400c61781601f58bef78ad581be499b733bc005a0255b5680cdf465951f440f9`
- U-Boot item SHA-256:
  `042759f9e366580405b8716a2815a2c0ab56fd76d218d5bb1a3c15864c9c973b`
- Source package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`
- Build commands:
  `APPLY_DISPLAY_MODE_PATCH=false scripts/build-vendor-uboot.sh --bootmenu --clean`
  `scripts/prepare-vendor-sd-hdmi-power-package.sh --uboot .build/u-boot/artifacts/bootmenu/u-boot-sun60iw2p1.bin --hdmi-default-mode 1280x720 --force-route --vendor /usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex --output /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-clockroute-720p.fex`
- Rationale: diagnostics from the previous package showed the DRM route,
  framebuffer, HPD, selected mode, and top PHY lock were all present, but the
  HDMI/TCON clock readings stayed at `24000000` while the selected pixel and
  TMDS clock were `74250` kHz. The packed U-Boot DTB exposed `clk_hdmi_gate`
  as `clk_hdmi`, so `_sunxi_drv_hdmi_set_rate()` was not programming the
  actual HDMI TV clock. This package assigns `/clocks/hdmi_tv` a phandle,
  exposes it as `clk_hdmi`, preserves the original gate as `clk_bus_hdmi`, and
  adds a U-Boot fallback that programs `clk_hdmi` from `drm_mode.clock` when
  the TCON clock reads as missing or stale 24 MHz.
- Extracted package DTB check:
  `hdmi clocks = 131 753 142 141 143 144`
  `clock-names = clk_tcon_tv clk_hdmi clk_hdmi_24M clk_bus_hdmi rst_main rst_sub`
- Reboot result: the selected `clk_hdmi` clock was now correct
  (`hdmi74250000`), but the top PHY registers read zero and no U-Boot visual
  was visible. That exposed a second driver issue: vendor U-Boot parses
  `clk_bus_hdmi` but did not enable it in `_sunxi_drv_hdmi_clock_on()`.

2026-07-03 custom bootmenu HDMI bus-clock 720p package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-busclock-720p.fex`
- Package SHA-256:
  `0a7a82b76e83cbb612c145c8f9414bb7dc7b4a5ce0c533c9cf002c4880337182`
- U-Boot item SHA-256:
  `50c3195cd076c8c8c3fedd596ecfc4fe034a505e7e50e8647b0a1acb426b622a`
- Source package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`
- Build commands:
  `APPLY_DISPLAY_MODE_PATCH=false scripts/build-vendor-uboot.sh --bootmenu --clean`
  `scripts/prepare-vendor-sd-hdmi-power-package.sh --uboot .build/u-boot/artifacts/bootmenu/u-boot-sun60iw2p1.bin --hdmi-default-mode 1280x720 --force-route --vendor /usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex --output /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-busclock-720p.fex`
- Rationale: keeps the corrected `clk_hdmi`/`clk_bus_hdmi` DTB binding and
  adds a source patch so `_sunxi_drv_hdmi_clock_on()` enables the parsed
  `clk_bus_hdmi` gate. Without that gate, the HDMI TV clock can be programmed
  but the HDMI/top-PHY block does not reliably produce pre-OS signal.
- Extracted package check:
  `hdmi clocks = 131 753 142 141 143 144`
  `clock-names = clk_tcon_tv clk_hdmi clk_hdmi_24M clk_bus_hdmi rst_main rst_sub`
  `grep -aF 'hdmi drv bus clock enable' u-boot.bin` matched once.

Installed framebuffer-test package:

- Package SHA-256:
  `831fad7f31e02c3fe099c2e83402ffc207d93ce2fe41272cb26fb8758fe9a2a0`.
- U-Boot item SHA-256:
  `472dd23358166ac1730513bcba60ec8606dba92d8ae87456bde61f851c5a5ae8`.
- Recovery backup:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T011715Z.bin`.
- Recovery backup SHA-256:
  `d44158d530b844a15b7420fa22404ae7a4c1ce8005b42b4c260510dbe4e84f3f`.
