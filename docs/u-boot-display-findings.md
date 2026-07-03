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

2026-07-03 stock BootGUI reset point:

- SPI NOR is present as `/dev/mtd0` (`XM25QU128C`, 16 MiB), but the current
  readback has no TOC magic hits and repeats the same 64 KiB content hash
  through the first MiB. Do not write SPI for the HDMI-selector problem unless
  a later capture proves the board is actually booting a valid SPI image.
- The SD boot0 region byte-matches the vendor `boot0_sdcard.fex`, so the
  missing factory splash is not caused by a corrupted SD boot0.
- The source path for the factory "initializing boot loader" display differs
  from the custom selector path that has been tested so far. Stock U-Boot keeps
  factory `boot.bmp`/`bootlogo` loader strings and uses the early display path
  around `sunxi_early_logo_display()` and `gd->boot_logo_addr`. The custom
  selector U-Boot packages prove that AW_DRM diagnostics can report success
  while the HDMI sink still sees no pre-OS signal.
- Next reset point package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_vendor-sd-scriptfirst.fex`
- Expected package SHA-256:
  `77ef94aee8f8a6ec27d130822b70187fbf4316773d7ae5d59150e9027c654670`
- Validate it before install with:

```bash
scripts/validate-stock-bootgui-package.sh \
  --package /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_vendor-sd-scriptfirst.fex
```

This package preserves the stock vendor U-Boot item and only changes distro
scan order from extlinux-first to script-first, so `boot.scr` can still stage
selector defaults while the factory display path is retested.

2026-07-03 HDMI rich-register diagnostic package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-richdiag-1024x600.fex`
- Package SHA-256:
  `d765d346f939de1438843a195b291cc7b9816c757da70b51d654876f1f815ba8`
- U-Boot item SHA-256:
  `317d6fe69c1e4aa1c727c0c24ef1a04e8a20d19209a7f7b4b7c8c1bf7bcfc2f5`
- Source package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`
- Build commands:
  `HOME=/root APPLY_DISPLAY_MODE_PATCH=true scripts/build-vendor-uboot.sh --bootmenu --clean`
  `scripts/prepare-vendor-sd-hdmi-power-package.sh --uboot .build/u-boot/artifacts/bootmenu/u-boot-sun60iw2p1.bin --hdmi-default-mode 1024x600 --force-route --vendor /usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex --output /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-richdiag-1024x600.fex`
- Rationale: prior tests proved the script path and NVMe boot handoff work, but
  the HDMI sink still sees black or no signal before Linux. This package keeps
  the corrected 1024x600 fallback, HDMI power, route, and clock handling, and
  extends `sunxi_hdmi_env` to export DesignWare PHY, mode-control, lock, and
  frame-composer registers in `opi_hdmi_diag`.
- Expected next evidence after the HDMI20 internal pattern test:
  `bootchooser=uboot-visual-hdmi20-pattern-ok` plus `opi_pre_hdmi=*`,
  `opi_pat_hdmipat=*`, and `opi_post_hdmi=*` fields containing
  `phy`, `stat`, `rst`, `lock`, `vid`, and `gcp` values.

2026-07-03 top-PHY PDDQ package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-toppddq-1024x600.fex`
- Package SHA-256:
  `d16c515ab57b1f2747d3706973633eed2b7a8ea47c1f3f90fbf398e0b0f28f37`
- U-Boot item SHA-256:
  `9ae2c1938a1b6be74460d37780475b626e2d087157b41486d6d32b27d1527d74`
- Source package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`
- Build command:
  `HOME=/root APPLY_DISPLAY_MODE_PATCH=true scripts/build-vendor-uboot.sh --bootmenu --clean`
- Rationale: the previous HDMI20-pattern reboot proved the script path and
  pattern register writes ran, but the monitor still had no visible pre-OS
  image. The captured top-PHY register was `top0_00000017`, which leaves the
  sun60i top-PHY `phy_pddq` bit asserted while reset, TX power, and HPD sense
  are also asserted. This package clears `phy_pddq` in the top-PHY ON path so
  the HDMI pads are not held in a power-down state during U-Boot output.
- Expected comparison after reboot: `top0_00000015` or another value with bit 1
  clear, plus the same `uboot-visual-hdmi20-pattern-ok` marker. If the monitor
  still has no pre-OS signal, continue from the new `top0`, `phy`, `stat`,
  `lock`, and pattern fields rather than changing selector/menu logic.

2026-07-03 corrected top-PHY PDDQ package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-toppddq-applied-1024x600.fex`
- Package SHA-256:
  `ee6df304753d62319a499f148d9e56b8a5f065f27548672ccb955f9cd93fc2a7`
- U-Boot item SHA-256:
  `84dd435604682491007d61d73ca0c460301a75fdacb8ef6d66288d54051b18c3`
- Raw built U-Boot SHA-256:
  `d2677f55cc482bf18c96c9ef5690ba93882a5cd03e45d7ac856334c7ea750726`
- Correction: the first top-PHY PDDQ package was built before `0013` was added
  to `scripts/build-vendor-uboot.sh`, so the package still had
  `phy_pddq = 0x1`. The build script now applies `0013` and fails if the
  generated work tree does not contain `phy_pddq = 0x0` before compiling.

2026-07-03 HDMI pattern reconfiguration package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-pattern-reconfig-1024x600.fex`
- Package SHA-256:
  `5e1e7209d7fe8535c998c640593f280a6b8f94f7afc4115cb11218189687d92d`
- U-Boot item SHA-256:
  `56e9e8e882485333850f928920f0d79914e0fd36b8f5a7af8ff2099301bae972`
- Raw built U-Boot SHA-256:
  `2b1b16851fffec7c10bf0a490d1d7884079a7f9c10b552fca6ce5de8671f33f8`
- Source package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`
- Build command:
  `HOME=/root APPLY_DISPLAY_MODE_PATCH=true scripts/build-vendor-uboot.sh --bootmenu --clean`
- Rationale: the corrected top-PHY package changed `top0_00000017` to
  `top0_00000015`, proving the new top-PHY code executed, but the DesignWare
  HDMI core status fields stayed zero while Linux later configured and locked
  HDMI successfully. This package forces `_sunxi_drv_hdmi_enable()` immediately
  before enabling the HDMI20 internal pattern and records its return value in
  `opi_hdmi_pattern_reconfig`.
- Expected comparison after reboot: the command line should contain
  `opi_pat_hdmipat=req1,reconfig0,...`. If pre-OS HDMI is still black or no
  signal, compare `opi_pre_hdmi`, `opi_pat_hdmi`, and `opi_post_hdmi` to see
  whether the forced reconfigure changed `phy`, `stat`, `rst`, `lock`, `vid`,
  or `gcp` from zero.

2026-07-03 stock-SD factory display retest:

- Upstream U-Boot source reference:
  `https://github.com/orangepi-xunlong/u-boot-orangepi`, branch `v2020.04`,
  commit `c97dbbcad55f5a1e40c28b1a9874b2e0b9f163c9`.
- Related NVMe DT research reference:
  `https://github.com/CarterPerez-dev/orangepi-4-pro-nvme-fix`, branch `main`,
  commit `fe4c31ec0115d3f2493905be07426f36f666aab5`. This is useful for A733
  NVMe/PCIe context, but it does not address U-Boot display.
- Installed package for the next test:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_vendor-sd-scriptfirst.fex`
- Package SHA-256:
  `77ef94aee8f8a6ec27d130822b70187fbf4316773d7ae5d59150e9027c654670`
- U-Boot item SHA-256:
  `94e5aa1cdebde42ce773f8d476fe78891cc61ad7e9e839d2554d738a549d55f5`
- Source stock SD package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package.fex`
- Source stock SD package SHA-256:
  `7a2661b080f5c5d8ba32566bc79f1ccfbfb8912a4a5c0c1a4856a9380542c807`
- Source stock SD U-Boot item SHA-256:
  `4d21321fba32d30b1dcc398c5850861db8f8dba213770e690ed6b51aae534533`
- Rationale: the custom HDMI diagnostic U-Boot proves `boot.scr` runs and the
  top PHY is powered, but the DesignWare HDMI core stays idle until Linux. The
  factory image's "initializing boot loader" display is known to work, so the
  next test returns to the stock SD U-Boot display/logo implementation and
  changes only the length-preserving distro scan order so `boot.scr` can run
  before extlinux.
- Staged behavior: `boot.scr` calls stock `sunxi_show_logo`, holds for 8
  seconds, enables `serial,vidconsole`, then enters prompted extlinux with
  NVMe as the default. Expected Linux marker after timeout/default selection is
  `bootchooser=extlinux-legacy-nvme`.

2026-07-03 HDMI full-reinit pattern package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-fullreinit-pattern-1024x600.fex`
- Package SHA-256:
  `5c70ff4fd05d4983ccaba08e22efece301ce2bf745618b0b1b46721823502a45`
- U-Boot item SHA-256:
  `e852404440cf42e0f7e9bcdb72306d6d11d436a32ddf0377090b2ba69666cead`
- Raw built U-Boot SHA-256:
  `351f591ace04907adfca5f5f3997792a1a92c5a9ad7682cc1ef3a210fd0606c0`
- Rationale: the prior low-level reinit returned `reconfig0`, but the
  DesignWare HDMI registers stayed idle. This package changes the pattern
  diagnostic to run the higher-level DRM HDMI sequence Linux uses after boot:
  disable, mode-set, enable, then apply the HDMI20 internal pattern.
- Expected comparison after reboot: `opi_pat_hdmipat=req1,reconfig0,...` should
  still appear, but `opi_post_hdmi` should show nonzero HDMI core fields or a
  visible red pattern. If it remains black/no-signal and the HDMI fields remain
  zero, the remaining gap is earlier than U-Boot's connector enable path.

2026-07-03 HDMI reinit stage-diagnostic package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-reinitdiag-pattern-1024x600.fex`
- Package SHA-256:
  `78b54a1b96aea7ca0456d8085d915e2eaedcffef6117e7d4ca6889eeb87c50e7`
- U-Boot item SHA-256:
  `ad176262afd51248a3c61ccff72185a66bea7fbf2916a012b0c3112210a0facf`
- Build command:
  `HOME=/root APPLY_DISPLAY_MODE_PATCH=true scripts/build-vendor-uboot.sh --bootmenu --clean`
- Rationale: the full-reinit package returned success but left the HDMI core
  registers at zero. The new `0016` patch bypasses the wrapper functions that
  swallow internal failures and records real return codes for driver disable,
  TCON exit, HDMI mode conversion, timing conversion, output select, display
  info setup, TCON init, HDMI clock rate, and `sunxi_hdmi_config()`.
- Expected comparison after reboot: the command line should include
  `opi_reinit_reinit=d...,x...,m...,t...,s...,i...,n...,r...,c...`.
  If the screen is still black before Linux, that field should identify the
  first failing stage or prove that all functions returned zero while the TOP
  PHY/DesignWare registers still stayed idle.

2026-07-03 DRM full-display reinit plus HDMI pattern package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-drm-reinit-hdmi-pattern-1024x600.fex`
- Package SHA-256:
  `34f52a23883a427d6471bdfc69654ef853a6f96a1f406a732acd64a35555852f`
- U-Boot item SHA-256:
  `bf4cbf09c7f910d4f3d9a8be3914606d7c5023a0bb6a63907c5cc96fb1f0fdf0`
- Build command:
  `HOME=/root APPLY_DISPLAY_MODE_PATCH=true scripts/build-vendor-uboot.sh --bootmenu --clean`
- Rationale: the stage diagnostic showed all connector-level HDMI reinit calls
  returned success while the visible signal still failed. This package adds
  `sunxi_drm reinit`, which runs the higher-level U-Boot display pipeline
  (`display_disable`, `display_init`, `display_enable`) before the HDMI20
  internal red-pattern test. It also reads DesignWare HDMI registers
  unconditionally because this BSP never sets `dw_hdmi.sw_init`.
- Expected comparison after reboot: the command line should include
  `opi_drmre_ok,drmreinit=...` if the full display reinit path completed, plus
  refreshed `opi_pre_hdmi`, `opi_reinit_reinit`, and `opi_post_hdmi` fields with
  real DesignWare register values instead of values hidden by `sw_init`.
- Result after reboot: unsafe. The board did not complete a normal boot from
  this package and required external SD recovery from another machine.
- Do not reinstall this package for normal testing. The SD installer now refuses
  this SHA-256 unless `ORANGEPI4PRO_ALLOW_UNSAFE_BOOTLOADER_WRITE=1` is set for
  deliberate bench recovery testing.

2026-07-03 recovered safe baseline:

- Installed SD TOC1 package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`
- Package SHA-256:
  `e626234a6eb9420ac29f515dd6acc543e7f0876e3dc086eec2fe221a50cc54f2`
- Verified state: byte-for-byte match in `/dev/mmcblk1` at `bs=8192`,
  `seek=2050`.
- Running marker:
  `bootchooser=extlinux-legacy-nvme`
- Current conclusion: boot reliability is restored with the vendor NVMe
  package, but pre-OS HDMI output is still absent. Further visual work should
  start from this known-good baseline and avoid reinstalling the failed DRM
  reinit package.

2026-07-03 BOOT_GUI source probe:

- `scripts/build-vendor-uboot.sh --bootgui-scriptfirst --clean` is a
  build-only probe. It applies only script-first distro scanning plus
  `configs/u-boot/orangepi4pro-bootgui.fragment`.
- The fragment enables the vendor legacy GUI path:
  `CONFIG_DISP2_SUNXI=y` and `CONFIG_BOOT_GUI=y`. It explicitly leaves
  `CONFIG_UPDATE_DISPLAY_MODE`, `CONFIG_BOOT_GUI_DOUBLE_BUF`, and
  `CONFIG_BOOT_GUI_TEST` disabled.
- With `CONFIG_UPDATE_DISPLAY_MODE=y`, the source fails earlier in
  `drivers/video/sunxi/bootGUI/dev_manage.c` with a redeclared local `i`.
- With `CONFIG_UPDATE_DISPLAY_MODE` disabled, the build reaches the legacy
  DISP2 display stack and then fails in `drivers/video/sunxi/disp2/disp`
  because A733/sun60iw2 is using the newer AW DRM display path. Representative
  failures include incomplete `struct disp_manager`, missing `DISP_*`
  constants, and missing `GFP_KERNEL`.

Conclusion: the factory-looking `BOOT_GUI` path is not a simple Kconfig fix
for this A733 branch. Enabling it pulls in a legacy display stack that is not
build-clean beside the current sun60iw2 AW DRM configuration. Keep this mode as
a reproducible negative probe only; do not package or install it as a boot test
candidate without source-level display-stack work.

2026-07-03 factory-logo preinit control-flow result:

- Installed package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_vendor-nvme-scriptfirst.fex`
- Package SHA-256:
  `d798104ccd705e542842fac409b1e2694c6ca19fcfac75fc30036a4535a7d318`
- Boot script result after reboot:
  `bootchooser=uboot-logo-preinit-ok bootchooser=boot-script-default-nvme`
- The display stayed black until the Linux/Ubuntu splash, even though
  `sunxi_show_logo` returned success.

Conclusion: boot-script ordering and logo-file lookup are not the remaining
blocker. The U-Boot DRM path believes it displayed a logo, but HDMI is not
delivering a valid visible signal until Linux later performs its full
1024x600 mode-change sequence.

2026-07-03 Linux frame-composer iteration candidate:

- Patch:
  `configs/u-boot/0019-sync-linux-hdmi-fc-iteration-and-diag.patch`
- Rationale: Linux's working HDMI20 path performs a frame-composer iteration
  write, `dw_write(FC_INVIDCONF, dw_read(FC_INVIDCONF))`, at the end of AVP
  configuration. The vendor U-Boot copy was missing this step. The same patch
  also removes the `sw_init` guard around diagnostic DesignWare register reads
  so `opi_hdmi_diag` reflects real register state instead of silently reporting
  zeros when U-Boot's software flag is stale.
- Build artifact:
  `.build/u-boot/artifacts/bootmenu/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `002934b2dec68ac776a3fa1dd1c84ff15d13ab0ebe0753d76ffb01b1c5b7bd11`
- Build source:
  Orange Pi U-Boot `v2018.05-sun60iw2`
  `b791be842935b27268ae3d00e943a9075495f30a`
- Safety: the known-unsafe full DRM reinit diagnostic remains disabled
  (`apply_drm_reinit_patch=false`), and the artifact strings do not contain
  `sunxi_drm reinit`.
- Planned package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-fciter-1024x600.fex`
- Planned test script: factory-logo preinit with a 15 second hold, defaulting
  through the known-good NVMe legacy `bootm` path.

2026-07-03 HDMI TCON clock-sequence candidate:

- Patch:
  `configs/u-boot/0018-use-linux-like-hdmi-tcon-clock-sequence.patch`
- Rationale: Linux's working HDMI enable path disables the TCON pixel and bus
  clocks, pulses the TCON reset, sets the 49 MHz pixel clock, then enables bus
  and pixel clocks. The U-Boot BSP was setting the HDMI TCON rate on top of the
  previous state. This can explain why framebuffer/logo calls report success
  while the monitor reports no pre-Linux signal.
- Build artifact:
  `.build/u-boot/artifacts/bootmenu/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `da53f596d657e984dc9e190499641f14dece4fa91887c170997dcf89bb2ce60b`
- Build source:
  Orange Pi U-Boot `v2018.05-sun60iw2`
  `b791be842935b27268ae3d00e943a9075495f30a`
- Safety change: `scripts/build-vendor-uboot.sh` now leaves the known-unsafe
  `0017` full DRM reinit diagnostic disabled unless
  `APPLY_DRM_REINIT_PATCH=true` is explicitly set.
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-tconseq-1024x600.fex`
- Package SHA-256:
  `18ed3b2a21c7c5a4563d21b426a2b0b34a972312c2bb0d1394ddfee74e199d49`
- U-Boot item SHA-256:
  `5cc7a6837af0f3ced7a554c9d5704bbdee056f3efa2af7b43a0dcedbf8d3df18`
- The package preserves vendor monitor/SCP, uses the A733 NVMe vendor package
  wrapper, keeps script-first scan order, applies existing HDMI power/CLDO2,
  `clk_tcon_tv`, 1024x600, and forced-route DTB corrections, and does not
  include the unsafe `sunxi_drm reinit` command.
