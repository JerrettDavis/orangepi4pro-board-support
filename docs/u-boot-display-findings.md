# U-Boot Display Findings

2026-07-04 recovery baseline:

- The board is booting NVMe Ubuntu through extlinux with
  `bootchooser=extlinux-legacy-nvme`.
- The active SD bootloader slot byte-matches the vendor NVMe package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`.
- Active package SHA-256:
  `e626234a6eb9420ac29f515dd6acc543e7f0876e3dc086eec2fe221a50cc54f2`
- The stock vendor SD package is:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package.fex`.
- Stock SD package SHA-256:
  `7a2661b080f5c5d8ba32566bc79f1ccfbfb8912a4a5c0c1a4856a9380542c807`
- Orange Pi's `/usr/lib/u-boot/platform_install.sh` writes
  `boot0_sdcard.fex` and `boot_package.fex` for SD installs. It uses the NVMe
  package only for the MTD/SPI path. Therefore the next bounded display test is
  to restore `boot_package.fex` to the SD bootloader slot while keeping the SD
  extlinux menu default pointed at the NVMe root.
- The vendor NVMe package plus mirrored `/boot/bootlogo.bmp`, `/boot/boot.bmp`,
  and `/boot/boot1.bmp` did not restore a pre-OS bootloader image. It did boot
  NVMe successfully, so the failure mode remains "invisible bootloader display"
  rather than "failed control flow".
- The 2026-07-04 desktop error popup was a stale LightDM crash report created
  during shutdown. It is tracked separately from U-Boot display work unless a
  fresh crash appears after the next test.
- Reinstalling the stock vendor SD package
  (`boot_package.fex`, SHA-256
  `7a2661b080f5c5d8ba32566bc79f1ccfbfb8912a4a5c0c1a4856a9380542c807`)
  preserved NVMe boot and restored the Ubuntu/Plymouth OS splash, but still
  did not show a bootloader splash. Since stock SD U-Boot scans extlinux before
  `boot.scr`, that reboot did not run the staged `sunxi_show_logo` hold.
- The next bounded test installs
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_vendor-sd-scriptfirst.fex`
  (SHA-256
  `77ef94aee8f8a6ec27d130822b70187fbf4316773d7ae5d59150e9027c654670`).
  This candidate is the stock SD U-Boot item with only the compiled distro scan
  order changed from extlinux-first to script-first; monitor and SCP payloads
  remain stock. It lets `/boot/boot.scr` call `sunxi_show_logo` and hold for
  20 seconds before NVMe boot, while avoiding custom HDMI reinit code.
- Result: the boot script did run and Linux reported
  `bootchooser=uboot-logo-preinit-ok`, but the display stayed black before
  Linux and the diagnostic bootm path removed the Plymouth OS splash. Source
  review showed the stock command can still return success even when
  `load_bmp_logo()` failed, because the return value is not tied to the logo
  load failure.
- Source review found the stock AW DRM loader uses
  `load_file(bmp_name, "bootloader")` and then
  `load_file(bmp_name, "boot-resource")`; it does not load
  `/boot/bootlogo.bmp` from the extlinux boot filesystem. The current SD card
  has one DOS Linux partition starting at sector 65536 and no named
  `boot-resource` partition. U-Boot's SDMMC logical offset is 40960 sectors,
  so a minimal Allwinner resource map can fit entirely in the zeroed reserved
  sector range 40960-65535.
- New guarded script:
  `scripts/stage-sd-boot-resource.sh`. Its dry-run creates four 16 KiB
  `softw411` MBR copies at absolute sector 40960, starts a FAT16
  `boot-resource` image at absolute sector 41088, ends at sector 65536, and
  copies `bootlogo.bmp`, `boot.bmp`, and `boot1.bmp` into that FAT image. The
  script defaults to dry-run and requires
  `ORANGEPI4PRO_ALLOW_BOOT_RESOURCE_WRITE=1 --yes` before writing.
- Result after installing the boot-resource area: no bootloader splash was
  visible, but the normal Ubuntu/Plymouth OS splash returned. Linux booted
  through `bootchooser=extlinux-legacy-nvme`, the SD TOC1 slot still matched
  `boot_package_vendor-sd-scriptfirst.fex`, and readback of sectors
  40960-65535 still contained the expected `softw411` MBR and `boot-resource`
  FAT image. Conclusion: missing resource partition was not sufficient to
  restore the factory pre-OS image on the current boot path. Further work
  needs a source-side U-Boot diagnostic that exports the exact
  `load_bmp_logo()` and `display_logo()` return codes before extlinux.

Captured 2026-07-02 after the video-first selector test hung before Linux.

2026-07-03 TOP PHY auto-calculation candidate:

- Linux becomes visible only after it runs a later HDMI disable/mode-set/enable
  cycle. In that path it logs `top phy auto calculate done` and programs the
  49 MHz `1024x600` mode with TOP PHY PLL value `0xE8193000`.
- The vendor U-Boot `phy_top.c` code was older than the kernel copy. It used a
  fixed table and did not have the Linux TOP PHY auto-calculation path for the
  cyberdeck panel's exact 49 MHz pixel clock.
- Patch `configs/u-boot/0021-sync-linux-top-phy-pll-autocal.patch` ports only
  that bounded TOP PHY PLL calculation into the U-Boot HDMI path. It does not
  enable the unsafe full DRM reinit command.
- The first reboot test should keep the existing 15-second HDMI20 pattern stage
  and check whether the U-Boot-exported HDMI diagnostics move from
  `top10_00000033` / `stat03` toward Linux's visible `top10=0x37` /
  `PHY_STAT0=0xf3` state.
- Test package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-topphy-autocal-1024x600.fex`
- Package SHA-256:
  `1e91636163adfb3cb9de1c7051e269596d5547877859edd17c82087b3506087f`
- Packaged U-Boot item SHA-256:
  `837084d8d16916713c8ae23e2b7690eb747373be6143914347df70dba9c52767`
- Raw built U-Boot artifact SHA-256:
  `81e5d7f9fc8fe52c777ee805cde0b4d1d1407004f501daa9f22aaca9eb145fde`
- The first reboot with that package still did not show a bootloader image and
  still exported `top10_00000033` / `stat03`. Patch
  `configs/u-boot/0022-add-top-phy-pll-env-diag.patch` adds the actual TOP PHY
  PLL/config words (`top20`, `top24`, `top28`, `top2c`, `top30`, `top40`) to
  the U-Boot-exported diagnostics. Linux visible state reads
  `top20=0xe8193000`, `top24=0x00000080`, `top40=0x00000001`,
  `top10=0x00000037`, `PHY_STAT0=0xf3`.
- Diagnostic package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-topphy-diag-1024x600.fex`
- Package SHA-256:
  `69cac94152ab5c8e9fa63a76fd6fbd0f6921cedc253d2b849b3ed82b8f7420ce`
- Packaged U-Boot item SHA-256:
  `f96ecb76a8570f4a8d456e5b3cd5f4637efb34d67eb8d1cc110caf5791aabf55`
- Raw built U-Boot artifact SHA-256:
  `b15d675fbe82d6950bd2ecaf410a737d0caca1f65f330125632b1f7cdc9126cb`
- The reboot with that package proved TOP PHY PLL parity but still showed
  `top10_00000033`, `stat03`, and `lock70`; Linux visible state has
  `top10=0x37`, `PHY_STAT0=0xf3`, and `MC_LOCKONCLOCK=0x79`.
- Patch `configs/u-boot/0023-sync-linux-hdmi-mc-clock-enable.patch` ports the
  Linux `dw_mc_clk_all_enable()` order: enable audio clock first, wait 20 ms,
  and leave PREP enabled. This directly targets the `lock70` to `lock79`
  difference without enabling the unsafe full DRM reinit path.
- MC clock-sequence package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-mcclk-1024x600.fex`
- Package SHA-256:
  `4d15d7c88b17aa1114aa99175ad489a4d3a36142430736fda2a4b113cb1e1844`
- Packaged U-Boot item SHA-256:
  `4febc8f1543f071fd12d63949e3ca7a79f7b030c7668c212029221c17cce46c1`
- Raw built U-Boot artifact SHA-256:
  `76cee5072f3f554eb26bdd93ee24dae1230cec83092e98c13c4ced0014071319`
- The reboot with that package still exported `top10_00000033`, `stat03`, and
  `lock70`, and the bootloader display stayed black until Linux. The Linux
  re-enable path also passes `disp_cfg.format` and `sw_enable` into the TCON
  HDMI init while U-Boot left those fields zero/default in the comparable
  path.
- Patch `configs/u-boot/0024-pass-hdmi-format-to-tcon-reinit.patch` passes
  `hdmi->disp_config.format` into both the normal U-Boot HDMI enable path and
  the bounded HDMI reinit diagnostic path, and records `fmt`/`sw` in
  `opi_reinit_reinit`.
- TCON format diagnostic package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-tconfmt-1024x600.fex`
- Package SHA-256:
  `1476e41aeae6bfeff49128146bfc5515beb03e3e2d83fad4c41bdf8d60ed6dec`
- Packaged U-Boot item SHA-256:
  `21b1fe5b5d03709d840b024d0d15ec96fe99a7e469c96189ed660a01b178fa5c`
- Raw built U-Boot artifact SHA-256:
  `ff649529abf00968a07c53eef5149b22776b285537ddf9c13f0ae56be910ade0`

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

2026-07-03 HDMI RX-sense wait candidate:

- Patch:
  `configs/u-boot/0020-wait-for-snps-phy-rxsense.patch`
- Rationale: the frame-composer test made U-Boot's HDMI core registers match
  Linux for `PHY_CONF0`, `MC_PHYRSTZ`, and `FC_INVIDCONF`, but U-Boot still
  reported `PHY_STAT0=0x03` while Linux-visible HDMI later reads
  `PHY_STAT0=0xf3`. The missing upper nibble is the four RX-sense lane bits.
  This patch waits up to 100 ms for RX-sense after SNPS PHY lock and records
  whether the wait timed out.
- Build artifact:
  `.build/u-boot/artifacts/bootmenu/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `7c9c6e781017a82dff400f5e31049cfdf69563d39b0b6d91aff2d5e31b5a4610`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-rxsense-1024x600.fex`
- Package SHA-256:
  `59fe28f8c629ff194e413cc7dd2878c6a6aec7103744a0422a4a1c537576d3ff`
- U-Boot item SHA-256:
  `1f0cd3409f43a11909f3b18f199554258c69b434332bbd8bf61e6fa05c07498b`
- Safety: the wait is bounded and non-fatal; it does not add or enable the
  unsafe full DRM reinit command.

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
- Package SHA-256:
  `a6ff4344d16002f4274a30fee0c4ed861fb6e4e1cedd9251a810ab38e69a2db0`
- U-Boot item SHA-256:
  `531c73cf5f7ace30e2dfba95e52a0beaa3beccf830984f92d5a259649967e556`
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

2026-07-03 standard U-Boot BMP-display result:

- Installed package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_vendor-nvme-scriptfirst.fex`
- Package SHA-256:
  `d798104ccd705e542842fac409b1e2694c6ca19fcfac75fc30036a4535a7d318`
- The staged boot script loaded a plain white `800x480` BMP and called standard
  U-Boot `bmp display ${load_addr}`. It then forced the known-good legacy NVMe
  `bootm` path so the diagnostic marker would survive.
- Reboot result: Linux reached `bootchooser=uboot-bmp-display-ok`, but no
  pre-OS image was visible before the Orange Pi OS splash. This proves the
  boot script ran and U-Boot's BMP command returned success; it does not prove
  HDMI scanout was active.

2026-07-03 staged stock-logo preinit diagnostic:

- The installed vendor-scriptfirst package still contains the upstream Orange
  Pi NVMe logo fallback strings: `sunxi_show_logo`, `boot.bmp decompressed OK`,
  and `NVMe detected ==> using embedded boot.bmp array`.
- The next boot test returns to the stock `sunxi_show_logo` command rather
  than `bmp display` or custom DRM reinit commands. The staged environment
  uses `selector_logo_preinit=true`, `selector_logo_hold=10`,
  `selector_bitmap=false`, and `selector_diag_force_bootm=true`.
- Expected marker after reboot:
  `bootchooser=uboot-logo-preinit-ok` or
  `bootchooser=uboot-logo-preinit-fail`.
- Safety: this test writes only `/boot`, `/boot/efi`, and the mounted SD
  `/boot` copy. It does not reinstall U-Boot or write bootloader sectors.
- Reboot result: Linux reached `bootchooser=uboot-logo-preinit-ok`, proving
  that the stock `sunxi_show_logo` command returned success before the legacy
  NVMe boot path. The command was still not visible on the HDMI display.

2026-07-03 passive stock-logo diagnostic package:

- Build command:
  `scripts/build-vendor-uboot.sh --scriptfirst-diag --clean`
- Build source:
  Orange Pi U-Boot `v2018.05-sun60iw2`
  `b791be842935b27268ae3d00e943a9075495f30a`
- Build artifact:
  `.build/u-boot/artifacts/scriptfirst-diag/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `357c962149d205e7f3f3822d3a47b97529ce6e5065cdc76044c9c496d5be45ed`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-scriptfirst-passive-diag.fex`
- Package SHA-256:
  `71cb5564f5d7249bece9c35a449bb199a9b6836dcb3f8dd2b946bea61b6b8ceb`
- U-Boot item SHA-256:
  `357c962149d205e7f3f3822d3a47b97529ce6e5065cdc76044c9c496d5be45ed`
- Scope: script-first scan order plus passive `sunxi_drm_env` and
  `sunxi_hdmi_env` commands only. The artifact preserves the embedded
  `boot.bmp` fallback and does not contain the known-unsafe `sunxi_drm reinit`
  command.
- Planned test: keep the stock-logo preinit path staged with
  `selector_diag_force_bootm=true`. The expected command line after reboot is
  `bootchooser=uboot-logo-preinit-ok` plus `opi_logo_hdmi=...` and
  `opi_logo_drm=...` diagnostics captured after `sunxi_show_logo`.

2026-07-04 recovery finding:

- External recovery restored the SD raw bootloader slot to the vendor NVMe TOC1
  package:
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`,
  `sha256=e626234a6eb9420ac29f515dd6acc543e7f0876e3dc086eec2fe221a50cc54f2`.
- `/dev/mtdblock0` did not contain a TOC1 header and appears erased, so current
  bootloader tests should treat `/dev/mmcblk1` offset `8192 * 2050` as the live
  bootloader source.
- Stock source review showed `sunxi_show_logo` hard-codes `bootlogo.bmp`.
  The active boot files contained `logo.bmp`, `boot.bmp`, and `boot1.bmp`, but
  no `bootlogo.bmp`. Before changing U-Boot again, the next test should restore
  the vendor logo asset under all three expected names and validate that the
  installed bootloader remains the vendor NVMe package.

2026-07-03 passive diagnostic reboot result:

- Reboot reached the NVMe Ubuntu root with `bootchooser=uboot-logo-preinit-ok`.
  The user still saw no bootloader image before the OS splash.
- Captured HDMI diagnostic:
  `fast0,hpd1,clk1,out1,drm1,mode1,tcon0,hdmi24000000,pix148500,tmds148500,toplock1,topclk0,toppad0,top0_00000017,top10_00000033,phy00,stat00,rst00,lock00,vid00,gcp00`.
- Captured DRM diagnostic:
  `n1,type=11,conn=hdmi-a,init=1,en=1,bl=1,mode=1920x1080,clk=148500,crtc=0,tcon=4,top=0,fb=0,fbw=1920,fbh=1080,force=0`.
- Interpretation: U-Boot reported HDMI/DRM enabled but selected
  `1920x1080` at a stale `24 MHz` HDMI clock, while Linux later reinitialized
  the display to the visible `1024x600` path. The next candidate therefore
  forces U-Boot's HDMI mode choice to the cyberdeck timing and sets `clk_hdmi`
  from the selected mode when the TCON clock is stale.

2026-07-03 script-first mode/clock forced diagnostic package:

- Build command:
  `scripts/build-vendor-uboot.sh --scriptfirst-diag-modeclock --clean`
- Build source:
  Orange Pi U-Boot `v2018.05-sun60iw2`
  `b791be842935b27268ae3d00e943a9075495f30a`
- Build artifact:
  `.build/u-boot/artifacts/scriptfirst-diag-modeclock/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `f56647ab3a8e1fa464e6fcf8d5731ef76c4b2ca4b5bd838ee75cc93318c65419`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-scriptfirst-diag-modeclock-force1024.fex`
- Package SHA-256:
  `be973352edaf182a456dc3618a91c17b12df4ba54ec4d0d8e8aa91aed8c48516`
- Scope: script-first scan order, passive `sunxi_drm_env` and
  `sunxi_hdmi_env`, forced U-Boot HDMI mode selection to `1024x600@49 MHz`,
  and HDMI clock fallback from the selected mode when the TCON clock is
  `0` or `24 MHz`. The package preserves the stock monitor and SCP blobs.
- Safety validation: package strings include `drm hdmi force cyberdeck mode`,
  `1024x600`, `sunxi_drm_env`, `sunxi_hdmi_env`, and script-first
  `scan_dev_for_boot`; they do not include `sunxi_drm reinit`.
- Reboot result: Linux reached `bootchooser=uboot-logo-preinit-ok` on the NVMe
  root. U-Boot now reported the desired selected mode:
  `mode=1024x600,clk=49000,fbw=1024,fbh=600`. The display still did not show a
  bootloader image. HDMI diagnostics still showed stale clock programming:
  `tcon0,hdmi24000000,pix49000,tmds49000`, so the next package keeps this
  U-Boot binary and patches the embedded DTB HDMI clock bindings so `clk_hdmi`
  resolves to the programmable `hdmi_tv` clock instead of the 24 MHz gate.

2026-07-03 forced cyberdeck-mode plus HDMI clock-DTB package:

- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-scriptfirst-diag-modeclock-force1024-hdmiclkdtb.fex`
- Package SHA-256:
  `78a8c9b079d96d33a396b1b1fc9f5bcf85c8fe80aee56e3777e20002bf3f5134`
- U-Boot item SHA-256:
  `65a9d1bec87a9d7e0dd41197ffc3f242f9437d342beae7d4f5eeccd1a2d9d5a6`
- Scope: same forced `1024x600@49 MHz` passive diagnostic U-Boot, plus the
  embedded DTB corrections from `prepare-vendor-sd-hdmi-power-package.sh`
  with `--fast-1024x600` and `force_route=false`. This normalizes HDMI clocks
  to `clk_tcon_tv clk_hdmi clk_hdmi_24M clk_bus_hdmi rst_main rst_sub`, adds
  the CLDO2 HDMI power rail properties, and keeps vendor monitor/SCP blobs.
- Safety validation: package strings include `drm hdmi force cyberdeck mode`,
  `1024x600`, `clk_tcon_tv`, `clk_bus_hdmi`, `sunxi_drm_env`,
  `sunxi_hdmi_env`, and script-first `scan_dev_for_boot`; they do not include
  `sunxi_drm reinit`.

2026-07-04 raw DE/TCON diagnostic package:

- Build command:
  `APPLY_DISPLAY_MODE_PATCH=true scripts/build-vendor-uboot.sh --bootmenu --clean`
- Build artifact:
  `.build/u-boot/artifacts/bootmenu/u-boot-sun60iw2p1.bin`
- U-Boot item SHA-256:
  `38ae59c77939ac73c06983b3e467aa3ee978b0ed05c0e211e077a5fe07f985a2`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-de-diag-hdmi-pattern-1024x600.fex`
- Package SHA-256:
  `969e19b6a3e231f7e65b686bbc5dfa07b6e7d37df6decefdf88f214cc9bf535b`
- SD TOC1 backup before install:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T040742Z.bin`
- Backup SHA-256:
  `0e9404b729eb5114b6058dca6a093c3d2861bc5b2e8077285b3dc52162895b54`
- Change: `configs/u-boot/0002-add-sunxi-drm-env-diag.patch` now adds a
  read-only `sunxi_de_env` command. It records selected DE, TCON4, and TCON
  TOP registers in `opi_de_diag` without changing display programming.
- Rationale: the prior 720p package reached NVMe and reported a locked HDMI
  core (`phy2e,stat03,lock70,vid78,gcp01`), but there was still no visible
  bootloader output. Linux later enables the same visible route
  (`DE-0 -> tcon4 -> HDMI-A`), so the next evidence needed is whether U-Boot's
  DE/TCON scanout state differs from Linux after the visual test.
- Expected reboot evidence: `/proc/cmdline` should include
  `bootchooser=uboot-visual-hdmi20-pattern-ok` and `opi_post_de=...` with
  `de=...`, `tcon=...`, and `top=...` register groups. Visual success remains
  a visible bootloader splash or selector before Linux starts.

- Reboot result: Linux reached NVMe with
  `bootchooser=uboot-visual-hdmi20-pattern-ok` and U-Boot recorded the new
  `opi_post_de=...` field, but this first raw diagnostic sampled TCON4
  (`0x05731000`) only. The packaged U-Boot DTB routes HDMI through
  `tcon3@5730000`, while `tcon4@5731000` is the EDP path. Linux live
  register reads after the visible mode set show the active HDMI TCON window at
  `0x05730000`, with nonzero registers at offsets `0x000`, `0x004`,
  `0x088`, `0x08c`, `0x090`, `0x098`, `0x09c`, `0x0a0`, `0x0a4`, `0x0a8`,
  and `0x0fc`. The next package corrects `sunxi_de_env` to report explicit
  TCON3 and TCON4 windows.

2026-07-04 TCON3/TCON4 corrected raw diagnostic package:

- Build command:
  `APPLY_DISPLAY_MODE_PATCH=true scripts/build-vendor-uboot.sh --bootmenu --clean`
- Build artifact:
  `.build/u-boot/artifacts/bootmenu/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `91b0bc3367142cb25c7dcc48bd4408feb1cfe88ff4121f8b143ce2b910d7aecc`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-tcon3diag-hdmi-pattern-1024x600.fex`
- Package SHA-256:
  `0381eff0a7a65ee407856b6ec9a10e4a0c82c8a4c3aa64f4f008b4b26024293f`
- U-Boot item SHA-256:
  `92334f2f929e1c8867902081c64a0335cd984be3c1189899c8500d8541a4ebb7`
- SD TOC1 backup before install:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T041753Z.bin`
- Backup SHA-256:
  `7188d42ff484a2c9ee7d9318ccae78bdb266c19438358c3a1cb710315c9e6a4a`
- Change: `sunxi_de_env` now records `t3=...` from `0x05730000`, `t4=...`
  from `0x05731000`, and selected TCON TOP values. This should distinguish a
  real TCON3 scanout failure from the earlier TCON4-only false negative.
- Expected reboot evidence: `/proc/cmdline` should include
  `bootchooser=uboot-visual-hdmi20-pattern-ok` and `opi_post_de=...t3=...`.
  If TCON3 is zero in U-Boot but nonzero under Linux, the fix path is the
  U-Boot TCON3 mode-init/open sequence. If TCON3 is already nonzero in U-Boot,
  the remaining failure is downstream of TCON scanout.

2026-07-04 current HDMI-chain 720p pattern package:

- Build command:
  `HOME=/root APPLY_DISPLAY_MODE_PATCH=false scripts/build-vendor-uboot.sh --bootmenu --clean`
- Packaging command:
  `scripts/prepare-vendor-sd-hdmi-power-package.sh --uboot .build/u-boot/artifacts/bootmenu/u-boot-sun60iw2p1.bin --hdmi-default-mode 1280x720 --force-route --vendor /usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex --output /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-current-720p.fex`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-current-720p.fex`
- Package SHA-256:
  `9d5d975f36049d614758dc3318d3d9af551f22ed3c3df8147e948057646f71c8`
- Build artifact SHA-256:
  `83a8e391827153cf126b1103de772d0093d03c3c37ad2ab9eee3dacb25e389bc`
- U-Boot item SHA-256:
  `3f44f36176542b0810312696e952dff7a6a3f96cbf69b612ba2068acefa3b68e`
- Backup before install:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T035255Z.bin`
- Backup SHA-256:
  `7735f99a818cfb8e600d052a00bd43d4011c9d71690ab122cbcd6fbac23c025f`
- Scope: this keeps the cumulative HDMI20 diagnostics, TOP PHY autocal, MC
  clock, TCON clock/format, and FC iteration patches, but disables the
  forced `1024x600` mode patch and packages the embedded U-Boot DTB with a
  standard `1280x720` HDMI default mode. The staged boot script runs
  `selector_visual_test=hdmi20_pattern` for 20 seconds.
- Expected reboot evidence: a visible red HDMI20 bootloader pattern before
  Linux starts would prove that the early HDMI path works at a standard mode.
  If the screen remains black but `/proc/cmdline` advances to a 720p
  `bootchooser=uboot-visual-hdmi20-pattern-ok` diagnostic, the remaining
  failure is still below the U-Boot command/reporting layer.

2026-07-04 bus-clock HDMI20 pattern result:

- Installed package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-busclock-720p.fex`
- Package SHA-256:
  `0a7a82b76e83cbb612c145c8f9414bb7dc7b4a5ce0c533c9cf002c4880337182`
- Reboot result: Linux reached NVMe with
  `bootchooser=uboot-visual-hdmi20-pattern-fail`. Unlike the stock
  script-first control, U-Boot populated diagnostics:
  `opi_pre_drm=n1,type=11,conn=hdmi-a,init=1,en=1,bl=1,mode=1280x720,clk=74250,...`,
  `opi_pre_hdmi=fast1,hpd1,clk1,out1,drm1,mode1,tcon24000000,hdmi74250000,pix74250,tmds74250,toplock1,...`,
  and matching `opi_post_*` values. This proves the diagnostic package ran and
  saw HPD, HDMI output, a 74.25 MHz HDMI clock, and top PHY lock before Linux.
- Remaining gap: `opi_pat_hdmipat=unset` because this older bus-clock package
  does not carry the HDMI pattern-status export patch. The screen still did
  not present a visible pre-Linux selector.

2026-07-04 pattern-status 1024x600 handoff:

- Installed package for next reboot:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-patternstatus-1024x600.fex`
- Package SHA-256:
  `2b79a35b9182a63a4304cb89aa1b1178fe214abe03050923b212a06e05a24abd`
- U-Boot item SHA-256:
  `63d7076c480805e6dbead46548ef1191c616337743ca9798c0f15afa29c57302`
- Safety/capability strings: contains `boot.scr`, `sunxi_hdmi20`,
  `sunxi_drm_env`, `sunxi_hdmi_env`, `opi_hdmi_pattern_diag`,
  `opi_hdmi_diag`, and `1024x600`; does not contain `sunxi_drm reinit` or
  `full hdmi reinit`.
- Install evidence: `scripts/install-sd-boot-package.sh` backed up the
  previous SD bootloader slot to
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T031045Z.bin`
  and verified the new SD TOC1 slot by readback.
- Expected evidence: `opi_pat_hdmipat=req1,...` should replace the previous
  `unset` value so the next iteration can distinguish a failed HDMI pattern
  command from a still-invisible but programmed HDMI frame-composer path.

2026-07-04 pattern-status 1024x600 result:

- Installed package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-patternstatus-1024x600.fex`
- Package SHA-256:
  `2b79a35b9182a63a4304cb89aa1b1178fe214abe03050923b212a06e05a24abd`
- Reboot result: Linux reached NVMe with
  `bootchooser=uboot-visual-hdmi20-pattern-ok`. U-Boot reported
  `mode=1024x600,clk=49000`, `hdmi49000000`, `toplock1`, and
  `opi_pat_hdmipat=req1,tcon0,force01,rff,g00,b00`. The pattern command
  returned success and programmed the HDMI frame-composer forced red pattern.
- If no red pre-Linux image was visible, the remaining failure is after the
  HDMI controller command path reports success. The next bounded test forces
  one `_sunxi_drv_hdmi_enable()` before enabling the internal pattern, without
  adding the known-unsafe full DRM reinit path.

2026-07-04 pattern-reconfigure handoff:

- Installed package for next reboot:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-pattern-reconfig-1024x600.fex`
- Package SHA-256:
  `5e1e7209d7fe8535c998c640593f280a6b8f94f7afc4115cb11218189687d92d`
- U-Boot item SHA-256:
  `56e9e8e882485333850f928920f0d79914e0fd36b8f5a7af8ff2099301bae972`
- Safety/capability strings: contains `boot.scr`, `sunxi_hdmi20`,
  `sunxi_drm_env`, `sunxi_hdmi_env`, `opi_hdmi_pattern_diag`,
  `opi_hdmi_pattern_reconfig`, `opi_hdmi_diag`, and `1024x600`; does not
  contain `sunxi_drm reinit` or `full hdmi reinit`.
- Install evidence: `scripts/install-sd-boot-package.sh` backed up the
  previous SD bootloader slot to
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T031632Z.bin`
  and verified the new SD TOC1 slot by readback.
- Expected evidence: `opi_pat_hdmipat=req1,reconfig0,...`. Visual success
  would be a red bootloader screen before Linux; diagnostic success without
  visual output will narrow the remaining issue to post-enable signal/display
  visibility.

2026-07-04 pattern-reconfigure result:

- Installed package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-pattern-reconfig-1024x600.fex`
- Package SHA-256:
  `5e1e7209d7fe8535c998c640593f280a6b8f94f7afc4115cb11218189687d92d`
- Reboot result: Linux reached NVMe with
  `bootchooser=uboot-visual-hdmi20-pattern-ok` and
  `opi_pat_hdmipat=req1,reconfig0,tcon0,force01,rff,g00,b00`.
  The bounded `_sunxi_drv_hdmi_enable()` returned success before the HDMI20
  forced-red pattern. U-Boot also reported the top-PHY PDDQ bit cleared
  (`top0_00000015`) but the direct DesignWare HDMI core diagnostics remained
  zero: `phy00,stat00,rst00,lock00,vid00,gcp00`.
- If no red pre-Linux image was visible, the next test applies the Linux-like
  frame-composer iteration patch and unconditional DesignWare register reads
  so the diagnostic path can distinguish stale software state from an actually
  idle HDMI core.

2026-07-04 frame-composer iteration handoff:

- Installed package for next reboot:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-fciter-1024x600.fex`
- Package SHA-256:
  `a6ff4344d16002f4274a30fee0c4ed861fb6e4e1cedd9251a810ab38e69a2db0`
- U-Boot item SHA-256:
  `531c73cf5f7ace30e2dfba95e52a0beaa3beccf830984f92d5a259649967e556`
- Source patch:
  `configs/u-boot/0019-sync-linux-hdmi-fc-iteration-and-diag.patch`
- Safety/capability strings: contains `boot.scr`, `sunxi_hdmi20`,
  `sunxi_drm_env`, `sunxi_hdmi_env`, `opi_hdmi_pattern_diag`,
  `opi_hdmi_pattern_reconfig`, `opi_hdmi_diag`, and `1024x600`; does not
  contain `sunxi_drm reinit` or `full hdmi reinit`.
- Install evidence: `scripts/install-sd-boot-package.sh` backed up the
  previous SD bootloader slot to
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T031946Z.bin`
  and verified the new SD TOC1 slot by readback.
- Expected evidence: the same `opi_pat_hdmipat=req1,reconfig0,...` path should
  boot, with post-reconfigure HDMI diagnostics showing whether the
  DesignWare core registers remain zero or move toward Linux's working state.

2026-07-04 frame-composer iteration result:

- Installed package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-fciter-1024x600.fex`
- Package SHA-256:
  `a6ff4344d16002f4274a30fee0c4ed861fb6e4e1cedd9251a810ab38e69a2db0`
- Reboot result: Linux reached NVMe with
  `bootchooser=uboot-visual-hdmi20-pattern-ok`. The direct DesignWare HDMI
  core diagnostics moved away from the previous all-zero values:
  `phy2e,stat03,rst00,lock70,vid58,gcp01`, with
  `opi_reinit_reinit=...core2e0300705801`. This proves the earlier zero core
  readings were stale/guarded diagnostics rather than a completely idle HDMI
  core. The remaining likely gap is RX-sense; U-Boot reports `stat03`, while
  Linux has previously shown upper RX-sense lane bits after HDMI becomes
  visible.

2026-07-04 RX-sense wait handoff:

- Installed package for next reboot:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-rxsense-1024x600.fex`
- Package SHA-256:
  `59fe28f8c629ff194e413cc7dd2878c6a6aec7103744a0422a4a1c537576d3ff`
- U-Boot item SHA-256:
  `1f0cd3409f43a11909f3b18f199554258c69b434332bbd8bf61e6fa05c07498b`
- Source patch:
  `configs/u-boot/0020-wait-for-snps-phy-rxsense.patch`
- Safety/capability strings: contains `boot.scr`, `sunxi_hdmi20`,
  `sunxi_drm_env`, `sunxi_hdmi_env`, `opi_hdmi_pattern_diag`,
  `opi_hdmi_pattern_reconfig`, `opi_hdmi_diag`, `rxsense`, and `1024x600`;
  does not contain `sunxi_drm reinit` or `full hdmi reinit`.
- Install evidence: `scripts/install-sd-boot-package.sh` backed up the
  previous SD bootloader slot to
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T032239Z.bin`
  and verified the new SD TOC1 slot by readback.
- Expected evidence: `PHY_STAT0` should either remain `stat03` after the
  bounded wait or move toward the later Linux-visible RX-sense state. Visual
  success would be a visible red bootloader pattern before Linux.

2026-07-04 RX-sense wait result:

- Installed package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-rxsense-1024x600.fex`
- Package SHA-256:
  `59fe28f8c629ff194e413cc7dd2878c6a6aec7103744a0422a4a1c537576d3ff`
- Reboot result: Linux reached NVMe with
  `bootchooser=uboot-visual-hdmi20-pattern-ok`, but the HDMI core state stayed
  at `phy2e,stat03,rst00,lock70,vid58,gcp01`. The bounded RX-sense wait did
  not move `PHY_STAT0` toward the later Linux-visible `0xf3` state.
- Interpretation: the next forward package should not repeat RX wait alone.
  Use the cumulative MC-clock candidate because it adds top-PHY PLL diagnostics
  and Linux-like HDMI main-controller clock sequencing, directly targeting the
  remaining `lock70` versus Linux-visible `lock79` difference.

2026-07-04 MC-clock handoff:

- Installed package for next reboot:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-mcclk-1024x600.fex`
- Package SHA-256:
  `4d15d7c88b17aa1114aa99175ad489a4d3a36142430736fda2a4b113cb1e1844`
- U-Boot item SHA-256:
  `4febc8f1543f071fd12d63949e3ca7a79f7b030c7668c212029221c17cce46c1`
- Source patches of interest:
  `0021-sync-linux-top-phy-pll-autocal.patch`,
  `0022-add-top-phy-pll-env-diag.patch`, and
  `0023-sync-linux-hdmi-mc-clock-enable.patch`.
- Safety/capability strings: contains `boot.scr`, `sunxi_hdmi20`,
  `sunxi_drm_env`, `sunxi_hdmi_env`, `opi_hdmi_pattern_diag`,
  `opi_hdmi_pattern_reconfig`, `opi_hdmi_diag`, `1024x600`,
  `top phy auto calculate done`, and `dw hdmi mc enable all clock`; does not
  contain `sunxi_drm reinit` or `full hdmi reinit`.
- Install evidence: `scripts/install-sd-boot-package.sh` backed up the
  previous SD bootloader slot to
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T032623Z.bin`
  and verified the new SD TOC1 slot by readback.
- Expected evidence: richer `top20_...top40_...` diagnostics plus whether
  `MC_LOCKONCLOCK` moves from `lock70` toward Linux's visible `lock79`.

2026-07-04 MC-clock result:

- Installed package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-mcclk-1024x600.fex`
- Package SHA-256:
  `4d15d7c88b17aa1114aa99175ad489a4d3a36142430736fda2a4b113cb1e1844`
- Reboot result: Linux reached NVMe with
  `bootchooser=uboot-visual-hdmi20-pattern-ok`. The richer top-PHY fields now
  matched the Linux PLL values:
  `top20_e8193000,top24_00000080,top28_00035000,top2c_00000000,top30_30000000,top40_00000001`.
  The HDMI core still reported `phy2e,stat03,rst00,lock70,vid58,gcp01`, so
  the MC-clock patch did not move `MC_LOCKONCLOCK` toward the later
  Linux-visible `lock79` state.

2026-07-04 TCON-format handoff:

- Installed package for next reboot:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-tconfmt-1024x600.fex`
- Package SHA-256:
  `1476e41aeae6bfeff49128146bfc5515beb03e3e2d83fad4c41bdf8d60ed6dec`
- U-Boot item SHA-256:
  `21b1fe5b5d03709d840b024d0d15ec96fe99a7e469c96189ed660a01b178fa5c`
- Source patch:
  `configs/u-boot/0024-pass-hdmi-format-to-tcon-reinit.patch`
- Safety/capability strings: contains `boot.scr`, `sunxi_hdmi20`,
  `sunxi_drm_env`, `sunxi_hdmi_env`, `opi_hdmi_pattern_diag`,
  `opi_hdmi_pattern_reconfig`, `opi_hdmi_diag`, `fmt%u`, `sw%d`,
  `top20_`, `dw hdmi mc enable all clock`, and `1024x600`; does not contain
  `sunxi_drm reinit` or `full hdmi reinit`.
- Install evidence: `scripts/install-sd-boot-package.sh` backed up the
  previous SD bootloader slot to
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T032919Z.bin`
  and verified the new SD TOC1 slot by readback.
- Expected evidence: `opi_reinit_reinit` should include `fmt...` and `sw...`
  fields, proving U-Boot passed the HDMI format and switch-enable values into
  TCON init before the bounded red-pattern hold.

2026-07-04 HDMI20 pattern retest with diagnostic-capable package:

- Control result: with
  `boot_package_vendor-sd-scriptfirst.fex`
  (`77ef94aee8f8a6ec27d130822b70187fbf4316773d7ae5d59150e9027c654670`),
  the staged `sunxi_hdmi20 pattern` script reached Linux with
  `bootchooser=uboot-visual-hdmi20-pattern-fail`, but all DRM/HDMI diagnostic
  variables were missing or unset. The stock script-first package does not
  contain `sunxi_hdmi20`, `sunxi_drm_env`, or `sunxi_hdmi_env`.
- Installed package for next reboot:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-hdmi-busclock-720p.fex`
- Package SHA-256:
  `0a7a82b76e83cbb612c145c8f9414bb7dc7b4a5ce0c533c9cf002c4880337182`
- U-Boot item SHA-256:
  `50c3195cd076c8c8c3fedd596ecfc4fe034a505e7e50e8647b0a1acb426b622a`
- Safety: package strings contain script-first `boot.scr`, `sunxi_hdmi20`,
  `sunxi_drm_env`, `sunxi_hdmi_env`, `opi_hdmi_diag`, and `opi_drm_diag`;
  they do not contain `sunxi_drm reinit` and do not match the two blocked
  recovery-required package hashes.
- Install evidence: `scripts/install-sd-boot-package.sh` backed up the
  previous SD bootloader slot to
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T030311Z.bin`
  and verified the written SD TOC1 slot by readback.
- Next expected evidence: `bootchooser=uboot-visual-hdmi20-pattern-ok` or
  `bootchooser=uboot-visual-hdmi20-pattern-fail` plus populated
  `opi_pre_*`, `opi_pat_hdmipat`, and `opi_post_*` diagnostics.

2026-07-04 BootGUI `logo` command diagnostic:

- Current installed SD TOC1 remains the stock vendor SD U-Boot with only the
  script-first scan-order patch:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_vendor-sd-scriptfirst.fex`,
  SHA-256 `77ef94aee8f8a6ec27d130822b70187fbf4316773d7ae5d59150e9027c654670`.
- The SD `boot0_sdcard.fex` region byte-matches the vendor file at
  `bs=8192 skip=1`, so boot0 is not the missing-display variable.
- Source review found two different factory logo paths. The prior tests used
  AW_DRM `sunxi_show_logo`; the vendor binary also contains the older BootGUI
  `logo` command, which calls `sunxi_bmp_display("bootlogo.bmp")`.
- The next low-risk test changes boot filesystem files only: stage
  `selector_logo_command=logo`, restore the Orange Pi BMP asset as
  `bootlogo.bmp`, `boot.bmp`, and `boot1.bmp`, hold for 20 seconds, then boot
  NVMe through the known-good legacy `bootm` path.
- Expected post-reboot evidence:
  `bootchooser=uboot-bootgui-logo-ok` or
  `bootchooser=uboot-bootgui-logo-fail`. A visible bootloader image during the
  hold would prove the factory BootGUI path is usable for the selector.
- Reboot result: Linux reached NVMe with
  `bootchooser=uboot-bootgui-logo-fail`. No bootloader image was visible; the
  Ubuntu/Plymouth OS splash was visible. The `logo` command path is therefore
  not usable with the current SD layout.
- Next bounded variable: remove the synthetic `boot-resource` area by restoring
  the pre-write reserved-window backup
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-boot-resource-before-20260704T022755Z.bin`
  and re-test. This restores the SD reserved area to the state before the
  boot-resource experiment, which did not improve the display and may affect
  Allwinner partition lookup.
- Restore action completed with
  `scripts/restore-sd-boot-resource-backup.sh --backup /var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-boot-resource-before-20260704T022755Z.bin --device /dev/mmcblk1 --yes`.
  Readback SHA-256 matched the backup:
  `cfadd44a103cbd6d5726fa07b27d7aad2f67ed3930ff96901c486a5beaf7e723`.
- Reboot result after restoring the reserved window: Linux again reached NVMe
  with `bootchooser=uboot-bootgui-logo-fail`; no bootloader image or selector
  was visible before the OS splash. The synthetic `boot-resource` area is
  therefore ruled out as the cause of the `logo` command failure.
- Next staged test: return to the documented AW_DRM/HDMI20 isolation path with
  `selector_visual_test=hdmi20_pattern`, `selector_visual_hold=20`,
  `selector_logo_preinit=false`, and the same script-first stock SD package.
  Expected post-reboot marker:
  `bootchooser=uboot-visual-hdmi20-pattern-ok` or
  `bootchooser=uboot-visual-hdmi20-pattern-fail`.
- Reboot result: Linux reached the NVMe root with
  `bootchooser=uboot-logo-preinit-ok`, but U-Boot exported
  `opi_logo_hdmi=drm-missing` and `opi_logo_drm=missing`. That proves even the
  clock-only embedded-DTB rewrite prevents the vendor DRM display list from
  being available at boot-script time. Do not use the embedded-DTB clock
  rewrite path for the next visual tests.

2026-07-03 HDMI TV clock fallback package:

- Build command:
  `scripts/build-vendor-uboot.sh --scriptfirst-diag-modeclock --clean`
- Build source:
  Orange Pi U-Boot `v2018.05-sun60iw2`
  `b791be842935b27268ae3d00e943a9075495f30a`
- Build artifact:
  `.build/u-boot/artifacts/scriptfirst-diag-modeclock/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `30173d1158694386a13d44a60f5a6dfca551ecc4640726a9fd0b8f8b6e0ce2e8`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-scriptfirst-diag-modeclock-force1024-hdmitvclk.fex`
- Package SHA-256:
  `000821770992c9124c51dddc360fb6dcd45f9bbe7f6c88bc72e07fdc953fa532`
- U-Boot item SHA-256:
  `30173d1158694386a13d44a60f5a6dfca551ecc4640726a9fd0b8f8b6e0ce2e8`
- Scope: stock embedded U-Boot DTB, vendor monitor/SCP blobs, script-first scan
  order, passive `sunxi_drm_env`/`sunxi_hdmi_env`, forced `1024x600@49 MHz`
  mode selection, and a code-side fallback that enables/programs the named
  `hdmi_tv` clock when the existing HDMI clock handle still reports `0` or
  `24 MHz`.
- Safety validation: package strings include `drm hdmi force cyberdeck mode`,
  `1024x600`, `sunxi_drm_env`, `sunxi_hdmi_env`, `tv%lu`, and script-first
  `scan_dev_for_boot`; they do not include `sunxi_drm reinit`.
- Expected reboot evidence: retain `bootchooser=uboot-logo-preinit-ok` and
  retained diagnostics instead of `drm-missing`; `opi_logo_hdmi` should include
  a `tv49000000`-style value if the named clock fallback worked.
- Reboot result: Linux reached the NVMe root and U-Boot diagnostics stayed
  present. `opi_logo_hdmi` reported `tv49000000`, proving the named `hdmi_tv`
  fallback worked, but the bootloader display stayed black. The remaining
  mismatch is the low-level PHY/MC state: U-Boot still reported `stat00` and
  `lock00`, while Linux later reinitialized HDMI and reached SNPS PHY lock.

2026-07-03 HDMI TV clock plus TOP/MC parity package:

- Build command:
  `scripts/build-vendor-uboot.sh --scriptfirst-diag-modeclock --clean`
- Build artifact:
  `.build/u-boot/artifacts/scriptfirst-diag-modeclock/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `bb53b2a56f12fb52d9db076890e1ac64adfb659a6ed2497acbb6e7ca25a4e21e`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-scriptfirst-diag-modeclock-force1024-hdmitvclk-topmc.fex`
- Package SHA-256:
  `9a71e37c0773a3b9d408d651db12037e7d7bbe5d7624244961f5610f38c89989`
- U-Boot item SHA-256:
  `bb53b2a56f12fb52d9db076890e1ac64adfb659a6ed2497acbb6e7ca25a4e21e`
- Scope: stock embedded U-Boot DTB, vendor monitor/SCP blobs, script-first scan
  order, passive `sunxi_drm_env`/`sunxi_hdmi_env`, forced `1024x600@49 MHz`,
  named `hdmi_tv` clock fallback, Linux TOP PHY PLL auto-calculation,
  Linux-like MC clock enable order, normal-path TCON format propagation, and
  passive TOP PHY register diagnostics. It does not include the unsafe full
  DRM reinit command.
- Expected reboot evidence: retain `bootchooser=uboot-logo-preinit-ok`, keep
  `tv49000000`, gain `top20_` through `top40_` diagnostics, and check whether
  `stat`/`lock` move from `00` toward Linux's locked state.
- Reboot result: Linux reached NVMe and U-Boot retained diagnostics. TOP PHY
  now matched Linux's visible PLL words:
  `top20_e8193000,top24_00000080,top28_00035000,top2c_00000000,top30_30000000,top40_00000001`.
  The bootloader display still stayed black because the DW/SNPS core state
  remained inactive: `phy00,stat00,rst00,lock00,vid00,gcp00`. Linux then made
  the display visible after a disable/re-enable sequence and reported SNPS PHY
  lock.

2026-07-03 stale HDMI enable-state retry package:

- Build command:
  `scripts/build-vendor-uboot.sh --scriptfirst-diag-modeclock --clean`
- Build artifact:
  `.build/u-boot/artifacts/scriptfirst-diag-modeclock/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `fe048ea27580f9248577f735380e40cbb31fd6893629285dbfa73b99581af1a5`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-scriptfirst-diag-modeclock-force1024-hdmitvclk-topmc-staleretry.fex`
- Package SHA-256:
  `d0d129a5718e0d8fb65f5c573ab793f67285988bf529a6361a6b763413e10658`
- U-Boot item SHA-256:
  `fe048ea27580f9248577f735380e40cbb31fd6893629285dbfa73b99581af1a5`
- Scope: same stock-DTB TOP/MC/TV-clock candidate, plus a normal-path retry
  inside `_sunxi_drv_hdmi_enable()`. If U-Boot believes HDMI is enabled but
  `PHY_STAT0` lacks TX lock or `MC_LOCKONCLOCK` lacks TMDS/pixel lock, it
  clears the stale enable state with `sunxi_hdmi_disconfig()` and continues
  through the existing normal `sunxi_hdmi_config()` path. The driver now marks
  `drv_enable=1` only after `sunxi_hdmi_config()` succeeds.
- Expected reboot evidence: if the stale early-return was the blocker,
  `opi_logo_hdmi` should move away from `phy00,stat00,rst00,lock00` toward
  SNPS PHY lock before Linux starts.
- Reboot result: Linux reached NVMe and retained U-Boot diagnostics, but the
  bootloader display stayed black and `opi_logo_hdmi` still showed
  `phy00,stat00,rst00,lock00`. The retry inside `_sunxi_drv_hdmi_enable()` was
  not enough because the successful stock logo path can return early from
  `display_enable()` when `state->is_enable` is already true.

2026-07-03 stale HDMI logo-path reinit package:

- Build command:
  `scripts/build-vendor-uboot.sh --scriptfirst-diag-modeclock --clean`
- Build artifact:
  `.build/u-boot/artifacts/scriptfirst-diag-modeclock/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `80f455d74201ac7209116b637851766532a4cfb516072894542c45bd1f38034a`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-scriptfirst-diag-modeclock-force1024-hdmitvclk-topmc-logorecover.fex`
- Package SHA-256:
  `8e8926949c5453fd1590341a8489120a52bc2e52f3c35c9bf384994f8d928efd`
- U-Boot item SHA-256:
  `80f455d74201ac7209116b637851766532a4cfb516072894542c45bd1f38034a`
- Scope: same stock-DTB TOP/MC/TV-clock candidate, plus
  `configs/u-boot/0030-recover-stale-hdmi-before-logo.patch`. The patch checks
  HDMI-A just before `display_logo()`. If the display state is initialized and
  enabled but `PHY_STAT0` lacks TX lock or `MC_LOCKONCLOCK` lacks TMDS/pixel
  lock, it records `opi_logo_recover`, calls `display_disable()`, calls
  `display_init()`, then lets the normal logo path draw and enable.
- Expected reboot evidence: `bootchooser=uboot-logo-preinit-ok` remains,
  `/proc/cmdline` gains `opi_logo_recover=stale-reinit-...`, and if this is
  the missing re-enable point, `opi_logo_hdmi` moves away from
  `phy00,stat00,rst00,lock00` before Linux starts.
- Reboot result: Linux reached NVMe and diagnostics stayed present, but
  `opi_logo_recover` was absent and `opi_logo_hdmi` still reported
  `phy00,stat00,rst00,lock00`. That means the pre-logo stale check did not
  match the state at its call site; after the normal logo path returns,
  U-Boot still thinks HDMI-A is initialized/enabled while the DW/SNPS core is
  unlocked.

2026-07-03 post-logo HDMI lock retry package:

- Build command:
  `scripts/build-vendor-uboot.sh --scriptfirst-diag-modeclock --clean`
- Build artifact:
  `.build/u-boot/artifacts/scriptfirst-diag-modeclock/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `f5f812a752f8dfb1674bf39c09e6130024d75498ffbf2a01db3392cbe30f4eab`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-scriptfirst-diag-modeclock-force1024-hdmitvclk-topmc-postlogoretry.fex`
- Package SHA-256:
  `540e7a150ce0a7c74feed86da3c3c5efd3262c6c628ab4efb3942e15791fac0f`
- U-Boot item SHA-256:
  `f5f812a752f8dfb1674bf39c09e6130024d75498ffbf2a01db3392cbe30f4eab`
- Patch:
  `configs/u-boot/0031-retry-unlocked-hdmi-after-logo-enable.patch`
- Change: after `display_logo()` draws the BMP and calls `display_enable()`,
  U-Boot now verifies HDMI-A lock. If the display state is still enabled but
  the PHY/MC lock registers remain unset, it performs one
  `display_disable()`/`display_init()`/`display_enable()` retry and records
  `opi_logo_recover=post-retry-...`.
- Expected reboot evidence: `/proc/cmdline` should gain
  `opi_logo_recover=post-retry-...`. A successful visual fix should also move
  `opi_logo_hdmi` away from `phy00,stat00,rst00,lock00` before Linux starts.
- Reboot result: Linux reached NVMe and U-Boot diagnostics stayed present, but
  `opi_logo_recover` was still absent and `opi_logo_hdmi` remained
  `phy00,stat00,rst00,lock00`. The post-logo guard still did not decide to
  retry, so the next package reports skip reasons and bases the retry decision
  directly on the DW/SNPS lock registers.

2026-07-03 relaxed post-logo HDMI retry package:

- Build command:
  `scripts/build-vendor-uboot.sh --scriptfirst-diag-modeclock --clean`
- Build artifact:
  `.build/u-boot/artifacts/scriptfirst-diag-modeclock/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `6337413c6991aed676e669e279db964e72163372626f84953a3e8c36e8a918bb`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-scriptfirst-diag-modeclock-force1024-hdmitvclk-topmc-relaxedretry.fex`
- Package SHA-256:
  `4e0941a6eb25f7a9e40a7496dc6957eea43f533e636b85813ee972ae5bf7cf9a`
- U-Boot item SHA-256:
  `6337413c6991aed676e669e279db964e72163372626f84953a3e8c36e8a918bb`
- Patch:
  `configs/u-boot/0032-relax-hdmi-logo-retry-and-report-skip.patch`
- Change: the post-logo retry now reads `PHY_STAT0` and `MC_LOCKONCLOCK`
  directly after `display_enable()`. If lock is missing, it retries
  `display_disable()`/`display_init()`/`display_enable()` without requiring
  `state->is_enable` or a connector type match. If it skips, it records either
  `opi_logo_recover=post-skip-not-init` or `opi_logo_recover=post-skip-locked`.
- Expected reboot evidence: `/proc/cmdline` must include
  `opi_logo_recover=post-retry-...`, `post-skip-not-init`, or
  `post-skip-locked`. The visual target remains a visible bootloader screen;
  the diagnostic target is to prove whether the retry is executing and whether
  HDMI lock changes before Linux starts.
- Reboot result: Linux reached NVMe and `opi_logo_recover=post-skip-locked`
  appeared. That means the immediate post-logo raw DW/SNPS lock read looked
  successful, but the bootloader display was still invisible and the later
  `sunxi_hdmi_env` diagnostic still read `phy00,stat00,rst00,lock00`. The next
  package stops treating immediate lock as success and forces one post-logo
  visible reinit.

2026-07-03 forced post-logo HDMI visible reinit package:

- Build command:
  `scripts/build-vendor-uboot.sh --scriptfirst-diag-modeclock --clean`
- Build artifact:
  `.build/u-boot/artifacts/scriptfirst-diag-modeclock/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `ca67510ad8e65130e29befbce2c0347e36fff1f8ecd6560bce3690f34d0e3087`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-scriptfirst-diag-modeclock-force1024-hdmitvclk-topmc-forcereinit.fex`
- Package SHA-256:
  `dac4949d4e5ad3fdb8c3db0bf16811f2ce8ed4948c242ffeebe3c052d940f7a1`
- U-Boot item SHA-256:
  `ca67510ad8e65130e29befbce2c0347e36fff1f8ecd6560bce3690f34d0e3087`
- Patch:
  `configs/u-boot/0033-force-post-logo-hdmi-reinit.patch`
- Change: after the normal logo draw/enable, U-Boot now performs one
  forced `display_disable()`/`display_init()`/`display_enable()` sequence even
  when the immediate DW/SNPS lock bits read as set. It records the existing
  `opi_logo_recover=post-retry-...` value with before/after PHY/MC lock bytes.
- Expected reboot evidence: `/proc/cmdline` should include
  `opi_logo_recover=post-retry-...`; visual success would be the bootloader
  splash/selector becoming visible before Linux starts.
- Reboot result: unsafe. The board did not complete normal startup and required
  external SD recovery from another machine. After recovery the system booted
  NVMe through `bootchooser=extlinux-legacy-nvme` without the U-Boot
  `opi_logo_*` diagnostic path. The package SHA
  `dac4949d4e5ad3fdb8c3db0bf16811f2ce8ed4948c242ffeebe3c052d940f7a1`
  is now blocked by `scripts/install-sd-boot-package.sh`, and patch
  `0033-force-post-logo-hdmi-reinit.patch` is not applied by the default
  `--scriptfirst-diag-modeclock` build path.

2026-07-03 forced cyberdeck-mode plus HDMI clock-only DTB package:

- Packaging command:
  `scripts/prepare-vendor-sd-hdmi-clock-package.sh --vendor /usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex --uboot .build/u-boot/artifacts/scriptfirst-diag-modeclock/u-boot-sun60iw2p1.bin --output /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-scriptfirst-diag-modeclock-force1024-hdmiclkonly.fex`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-scriptfirst-diag-modeclock-force1024-hdmiclkonly.fex`
- Package SHA-256:
  `30a2e74b02aaaef585c38775c8cf31b73763a0f4ed09d563d1e3c3d213b91ddd`
- U-Boot item SHA-256:
  `c2b16f210805d35bae323bd646855c8e29e7e6763d5c14989a5d278e39f75d48`
- Scope: same forced `1024x600@49 MHz` passive diagnostic U-Boot, plus only
  embedded DTB HDMI clock binding normalization:
  `clk_tcon_tv clk_hdmi clk_hdmi_24M clk_bus_hdmi rst_main rst_sub`.
  It does not add CLDO2 HDMI power properties, does not set fast-output, does
  not force the HDMI route, and preserves vendor monitor/SCP blobs.
- Safety validation: package strings include `drm hdmi force cyberdeck mode`,
  `1024x600`, `clk_tcon_tv`, `clk_bus_hdmi`, `sunxi_drm_env`,
  `sunxi_hdmi_env`, and script-first `scan_dev_for_boot`; they do not include
  `sunxi_drm reinit`.

2026-07-04 bootmenu RX-sense stale-state test:

- Live Linux-visible HDMI byte reads showed the HDMI controller state that
  actually produces a picture:
  `PHY_STAT0=0xf3`, `MC_LOCKONCLOCK=0x79`, and `FC_PACKET_TX_EN=0x1f`.
- The previous U-Boot handoff reported `stat03` and `lock70`. That has HPD,
  PHY lock, pixel lock, and TMDS lock, but no RX-sense bits. The old stale
  checks treated this as usable HDMI even though the monitor stayed black until
  Linux performed a later full HDMI atomic disable/enable.
- `configs/u-boot/0029-retry-stale-hdmi-enable-state.patch` and
  `configs/u-boot/0032-relax-hdmi-logo-retry-and-report-skip.patch` now require
  `PHY_STAT0_RX_SENSE_ALL_MASK` before U-Boot skips HDMI reconfiguration.
- `scripts/build-vendor-uboot.sh --bootmenu` now applies the stale-enable and
  logo-retry patches so the visual-selector build path actually contains this
  RX-sense check.
- Build artifact SHA-256:
  `9e289fab52d09d76f967b2e664765500f33ebc1d06003982b9eff920858550d4`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_a733-custom-bootmenu-rxsense-stale-retry-hdmi-pattern-1024x600.fex`
- Package SHA-256:
  `feacc7a99a48a1f6a64318b8372042f0b24df36bc5bae1f35f4bcc36581e6438`
- U-Boot item SHA-256:
  `dc8fabad16732d543f76b584e211b02e741eb4f0cdbbff4db9887a35517e3975`
- SD backup before install:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T043036Z.bin`
- Backup SHA-256:
  `d8dcda3f1f422f972d57cd761bcd3c179c42ef5c218e629179a7c2d161dfb2ef`
- Reboot result: unsafe. The board did not complete a normal boot and required
  external WSL recovery. After recovery, the system booted NVMe through
  `bootchooser=extlinux-legacy-nvme` without the U-Boot visual diagnostic
  markers. The package SHA
  `feacc7a99a48a1f6a64318b8372042f0b24df36bc5bae1f35f4bcc36581e6438` is now
  blocked by `scripts/install-sd-boot-package.sh`.

2026-07-04 delayed `sunxi_show_logo` HPD test:

- Rationale: Linux does not reliably finish HDMI configuration until several
  seconds after early boot. Recent user-visible behavior also included a
  monitor-side `no signal` period before Linux/plymouth or the desktop became
  visible. This test leaves the vendor embedded-logo path intact and adds only
  a 5-second delay immediately before AW_DRM `sunxi_show_logo()` draws the
  factory image.
- Build command:
  `scripts/build-vendor-uboot.sh --bootgui-hpd-delay --clean`
- Patch:
  `configs/u-boot/0033-delay-sunxi-show-logo-for-hdmi-hpd.patch`
- Build artifact:
  `.build/u-boot/artifacts/bootgui-hpd-delay/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `e10c6eab23b27993cfbdd65c85afac1bc16d4e5570ed4ed57f43ddb3bec84f55`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_nvme-scriptfirst-sunxi-show-logo-delay.fex`
- Package SHA-256:
  `65eaba1bff9c98324213d0a6c4849f2dccf74de2b115e4edb724ed63a29e6012`
- U-Boot item SHA-256:
  `e10c6eab23b27993cfbdd65c85afac1bc16d4e5570ed4ed57f43ddb3bec84f55`
- SD backup before install:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T164212Z.bin`
- Backup SHA-256:
  `513388dd8c9ee53412ea2742427550c97c1a929144c8a681afd4da63cdded2be`
- Installed-slot validation: the SD TOC1 slot at `bs=8192 skip=2050`
  byte-matched the package SHA
  `65eaba1bff9c98324213d0a6c4849f2dccf74de2b115e4edb724ed63a29e6012`.
- Safety validation: `scripts/validate-sunxi-logo-delay-package.sh` requires
  script-first scan order, `boot.bmp decompressed OK`, `embedded boot.bmp
  array`, `sysboot`, `extlinux.conf`, and the exact
  `Orange Pi 4 Pro: waiting 5 seconds before sunxi_show_logo` marker. It
  rejects the previously unsafe RX-sense, stale-logo-retry, post-logo-retry,
  file-backed boot1.bmp, and high-contrast selector payload strings.
- Expected reboot evidence: the display should no longer report `no signal`
  during the 15-second U-Boot logo hold. The boot script should still reach
  `bootchooser=uboot-logo-preinit-ok` before extlinux boots the default NVMe
  Ubuntu entry.
- Reboot result: failed visually. The board booted back to NVMe Ubuntu, but
  the display stayed black/no-signal until Linux/desktop. The running kernel
  command line reported `bootchooser=extlinux-legacy-nvme`; the extlinux path
  does not preserve the U-Boot logo diagnostics, so this test did not capture
  whether `sunxi_show_logo()` reached the HDMI locked state.

2026-07-04 delayed logo plus passive HDMI/DRM diagnostics:

- Rationale: the delay-only package still produced no visible bootloader image,
  and extlinux overwrote the U-Boot diagnostic marker. This package keeps the
  same delayed factory-logo path but also includes only passive
  `sunxi_drm_env` and `sunxi_hdmi_env` commands. The staged boot script uses
  `selector_diag_force_bootm=true` for one reboot so those diagnostics survive
  into `/proc/cmdline`.
- Build command:
  `scripts/build-vendor-uboot.sh --logo-delay-diag --clean`
- Build artifact:
  `.build/u-boot/artifacts/logo-delay-diag/u-boot-sun60iw2p1.bin`
- Build artifact SHA-256:
  `b6d35454586a5bb634fd9a899d567837b106493be04d7273e73b9f51beb39466`
- Package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_nvme-scriptfirst-logo-delay-diag.fex`
- Package SHA-256:
  `17c107db643f858b289e600abed5ad9aee3edd0949f1a2a7fb381bebd07caf2a`
- U-Boot item SHA-256:
  `b6d35454586a5bb634fd9a899d567837b106493be04d7273e73b9f51beb39466`
- SD backup before install:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T165041Z.bin`
- Backup SHA-256:
  `f0ba7e5ca7c0d40acd12b1986ffcf00e0041cf1b0f9c7c78639e5e3a523f5de9`
- Installed-slot validation: the SD TOC1 slot at `bs=8192 skip=2050`
  byte-matched package SHA
  `17c107db643f858b289e600abed5ad9aee3edd0949f1a2a7fb381bebd07caf2a`.
- Safety validation: `scripts/validate-sunxi-logo-delay-package.sh
  --require-diag` requires the delayed embedded-logo path and the passive
  HDMI/DRM diagnostic commands. The package still excludes the known-unsafe
  RX-sense wait, full DRM reinit, post-logo HDMI retry, stale-logo recovery,
  file-backed `boot1.bmp`, and high-contrast selector payload strings.
- Expected reboot evidence: if the screen is still black, `/proc/cmdline`
  should include `bootchooser=uboot-logo-preinit-ok` plus `opi_logo_hdmi=...`
  and `opi_logo_drm=...`, giving the U-Boot-side HDMI/DRM state at the failed
  visual point.
- Reboot result: failed visually, but captured useful diagnostics. The display
  still stayed black before Linux/plymouth. `/proc/cmdline` preserved
  `bootchooser=uboot-logo-preinit-ok` and reported U-Boot HDMI/DRM state:
  `opi_logo_drm=n1,type=11,conn=hdmi-a,init=1,en=1,...,mode=1920x1080,clk=148500`
  and
  `opi_logo_hdmi=fast0,hpd1,clk1,out1,drm1,...,hdmi24000000,pix148500,...,phy00,stat00,rst00,lock00`.
  Interpretation: U-Boot reached the delayed logo path and believed HDMI-A was
  enabled, but the low-level HDMI block remained idle/unlocked until Linux
  later reinitialized display.

2026-07-04 U-Boot spare-header post-processing fix:

- Finding: every locally rebuilt U-Boot artifact had an incomplete Allwinner
  spare header because the public vendor tree invokes
  `scripts/sunxi_ubootools`, which is an x86-64 executable and fails on this
  ARM board with `Exec format error`. The resulting U-Boot item still boots
  from TOC1, but its header checksum field remains the stamp value
  `0x5f0a6c39`, and `length`/`uboot_length` remain zero.
- Stock comparison: the Orange Pi package
  `/usr/lib/linux-u-boot-current-orangepi4pro_1.0.6_arm64/boot_package_a733_nvme.fex`
  has populated U-Boot header metadata (`length=1163264`,
  `uboot_length=1163264`) and a valid spare-header checksum.
- Fix: `scripts/fix-sunxi-uboot-header.py` now runs after a successful build,
  pads U-Boot binaries to a 4-byte boundary, sets `length` and
  `uboot_length`, and recomputes the Allwinner word-sum checksum using stamp
  `0x5f0a6c39`.
- Rebuilt command:
  `scripts/build-vendor-uboot.sh --logo-delay-diag --clean`
- Fixed build artifact:
  `.build/u-boot/artifacts/logo-delay-diag/u-boot-sun60iw2p1.bin`
- Fixed build artifact SHA-256:
  `592231881302f90524aa9c36bdb134335283fc3b266b42f97f787b3cdde0bce5`
- Fixed package:
  `/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_nvme-logo-delay-diag-fixed-header.fex`
- Fixed package SHA-256:
  `eae2651699fa2c14556124f68dbc33f9d9c8dd298f0ee41574582f7a531e713e`
- Package validation: TOC1 checksum is valid; monitor and SCP items still match
  stock; U-Boot item length is `1194708`; U-Boot spare header has
  `length=1194708`, `uboot_length=1194708`, and validates with
  `scripts/fix-sunxi-uboot-header.py --verify`.
- SD backup before install:
  `/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260704T171105Z.bin`
- Backup SHA-256:
  `17c2cb8ba2ffcdca5ecca9b15741afa0091ebc5673dc35a9eb67b77e3dbe77ec`
- Installed-slot validation: the SD TOC1 slot at `bs=8192 skip=2050`
  byte-matched package SHA
  `eae2651699fa2c14556124f68dbc33f9d9c8dd298f0ee41574582f7a531e713e`.
- Safety validation: required strings `scan_dev_for_scripts; run
  scan_dev_for_extlinux`, `sunxi_drm_env`, `sunxi_hdmi_env`, and `waiting 5
  seconds before sunxi_show_logo` are present. Known-unsafe strings
  `sunxi_drm reinit`, `force visible reinit`, `post-logo visible reinit`,
  `BOOTLOADER TEST SCREEN`, `dw_phy_wait_rxsense`, `refresh stale HDMI enable
  before logo`, and `pre-enable-refresh` are absent.
- Failed branch recorded but not retained as a build mode: enabling
  `DISP2_SUNXI`/`CONFIG_BOOT_GUI` for sun60iw2 proved non-viable in the public
  source because `drivers/video/sunxi/disp2` fails to compile with
  `#error "undefined platform!!!"`. This suggests the visible factory splash is
  not recoverable by simply enabling the legacy DISP2 BootGUI stack in this
  branch.
