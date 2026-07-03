# Vendor U-Boot Boot Menu Build

This board currently boots through Orange Pi's Allwinner BSP U-Boot for the
A733 / sun60iw2 platform. The installed package is usable for extlinux, but it
does not provide a familiar GRUB EFI path:

- `CONFIG_EFI_LOADER` is not set in the installed package.
- The BSP U-Boot build is a 32-bit ARM loader, so enabling EFI would advertise
  `bootarm.efi`, not the normal AArch64 `bootaa64.efi` path expected by GRUB on
  this 64-bit Linux system.
- The current practical selector path is U-Boot `bootmenu` plus extlinux, not
  GRUB EFI.

## Source Pin

Verified 2026-07-02:

| Field | Value |
| --- | --- |
| URL | `https://github.com/orangepi-xunlong/u-boot-orangepi.git` |
| Branch | `v2018.05-sun60iw2` |
| Commit | `b791be842935b27268ae3d00e943a9075495f30a` |
| Commit date | `2026-03-04 21:25:33 +0800` |
| Subject | `sun60iw2: fix nvme boot and update logo config` |
| Defconfig | `sun60iw2p1_t736_defconfig` |

## Build Requirements

On the Orange Pi Ubuntu Jammy image:

```bash
sudo apt-get install -y \
  bc bison build-essential device-tree-compiler flex git \
  gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi \
  python3-dev swig
```

The BSP tree needs these build constraints on this host:

- `CROSS_COMPILE=arm-linux-gnueabi-`
- `DTC=/usr/bin/dtc`
- `PWD=$work_dir`
- `KCFLAGS=-Wno-error`
- `LICHEE_CHIP_CONFIG_DIR` and `LICHEE_PLAT_OUT` redirected away from `/`

The vendor tree contains a shipped `scripts/sunxi_ubootools` binary that is not
native to this ARM host. The build still produces `u-boot.bin` and
`u-boot-sun60iw2p1.bin`.

The installed `boot_package*.fex` files are Allwinner TOC1 packages. The header
uses magic `0x89119800`, item descriptors, and the stock checksum formula used
by the BSP:

```text
checksum = sum(all little-endian 32-bit words except checksum field) + 0x5f0a6c39
```

Use the file-only helper to inspect or rebuild package files:

```bash
scripts/sunxi-toc1-package.py inspect /path/to/boot_package_a733_nvme.fex
scripts/sunxi-toc1-package.py repack \
  --template /path/to/boot_package_a733_nvme.fex \
  --replace u-boot=/path/to/u-boot-sun60iw2p1.bin \
  --output /tmp/boot_package_a733_nvme-bootmenu.fex
```

The helper never flashes media, writes block devices, writes MTD devices, or
installs a bootloader.

On the current cyberdeck boot setup, the SPI flash readback was erased and the
active bootloader package was found in the SD-card bootloader area:

```text
boot0_sdcard.fex -> /dev/mmcblk1, bs=8k seek=1
boot_package.fex -> /dev/mmcblk1, bs=8k seek=2050
```

Use the guarded SD installer only after a candidate package has been inspected
and the repo state has been committed and pushed:

```bash
scripts/install-sd-boot-package.sh \
  --package /path/to/boot_package-bootmenu.fex

ORANGEPI4PRO_ALLOW_BOOTLOADER_WRITE=1 \
  scripts/install-sd-boot-package.sh \
  --package /path/to/boot_package-bootmenu.fex \
  --yes
```

The installer backs up the SD bootloader range before writing and verifies the
written bytes. It does not write boot0, NVMe, SPI/MTD, partitions, filesystems,
or firmware.

Prepare or refresh the script-first package candidate without installing it:

```bash
scripts/prepare-sd-bootmenu-package.sh
```

The prep script is file-only. It validates that the U-Boot artifact contains
`run scan_dev_for_scripts; run scan_dev_for_extlinux` and writes the candidate
under `/var/cache/orangepi4pro-images/build/boot-package-candidates/`.

Build the script-first menu variant with a replacement embedded boot logo:

```bash
scripts/build-vendor-uboot.sh --selector-logo --clean
scripts/prepare-sd-bootmenu-package.sh \
  --uboot .build/u-boot/artifacts/bootmenu-selector-logo/u-boot-sun60iw2p1.bin \
  --output /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu-scriptfirst-selector-logo.fex
```

This keeps the display path in the vendor early-logo code and avoids calling
`sunxi_show_bmp` from `/boot/boot.scr`, which hung this board during testing.
The generated BMP is also staged as
`.build/u-boot/artifacts/bootmenu-selector-logo/selector-boot.bmp` for visual
inspection.

Build the script-first menu variant with the replacement embedded boot logo and
the U-Boot DRM environment diagnostic command:

```bash
scripts/build-vendor-uboot.sh --selector-logo --clean
scripts/prepare-sd-bootmenu-package.sh \
  --uboot .build/u-boot/artifacts/bootmenu-selector-logo/u-boot-sun60iw2p1.bin \
  --output /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu-scriptfirst-selector-logo-drm-env.fex
```

This variant adds `sunxi_drm_env`, which exports the vendor DRM connector,
mode, framebuffer, and backlight state into `opi_drm_diag`. It is intended for
boot-script diagnostics and does not draw graphics by itself.

Build the cyberdeck-native HDMI fallback variant:

```bash
scripts/build-vendor-uboot.sh --selector-logo --clean
scripts/prepare-sd-bootmenu-package.sh \
  --uboot .build/u-boot/artifacts/bootmenu-selector-logo/u-boot-sun60iw2p1.bin \
  --output /var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu-scriptfirst-selector-logo-drm-env-1024x600.fex
```

This keeps the same script-first bootmenu and diagnostics, but changes vendor
U-Boot's no-EDID HDMI fallback from `1920x1080` to the panel's Linux-proven
`1024x600` timing: 49.00 MHz, `1024 1029 1042 1312 600 602 605 622`,
negative hsync, positive vsync.

## Menu Fragment

`configs/u-boot/orangepi4pro-bootmenu.fragment` enables:

- `CONFIG_CMD_BOOTMENU=y`
- `CONFIG_AUTOBOOT_MENU_SHOW=y`
- `CONFIG_USB_KEYBOARD=y`
- `CONFIG_SYS_USB_EVENT_POLL=y`
- `CONFIG_DM_KEYBOARD=y`
- `# CONFIG_EFI_LOADER is not set`

`configs/u-boot/0001-distro-scan-scripts-before-extlinux.patch` changes the
compiled distro boot environment so U-Boot scans `boot.scr` before extlinux:

```text
run scan_dev_for_scripts
run scan_dev_for_extlinux
```

The stock order is extlinux first. On this board that means extlinux boots the
default entry before `/boot/boot.scr` can run, so boot-script-level menu changes
are ignored.

## Reproducible Build

Build the tested menu variant:

```bash
scripts/build-vendor-uboot.sh --bootmenu --clean
```

Build the baseline defconfig without the menu fragment:

```bash
scripts/build-vendor-uboot.sh --baseline --clean
```

Artifacts are staged under `.build/u-boot/artifacts/`. The script does not run
`dd`, write `/dev/nvme0n1`, write `/dev/mmcblk*`, erase SPI, or install a
bootloader.

## Installed Test Status

The current cyberdeck SD card was recovered externally to an extlinux-first
package after the video-first selector test hung. The validated script-first
package below was installed and proven to reach Linux, but it is not the live
bootloader package after recovery:

```text
device=/dev/mmcblk1
package=/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu-scriptfirst.fex
package_sha256=8a0393cbbbd27b980f8b7c2e9fc5070b3c1dd79aaf5b42f189f66daa00202289
u_boot_item_sha256=f57faf0cc956e639176f48996c2388cfbb8c749d5707d872b09249dcebef3845
backup=/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260702T222612Z.bin
backup_sha256=55dcadb7f255ad4c6489dd8fc34d07af2eac0d2110a06a20a2546775378f214e
```

The installed bytes were read back from `/dev/mmcblk1` at `bs=8192 skip=2050`
and matched the candidate package exactly.

The installed 2026-07-02 recovery-SD test candidate uses the same script-first
bootmenu U-Boot plus an embedded selector logo generated at build time:

```text
device=/dev/mmcblk1
package=/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu-scriptfirst-selector-logo.fex
package_sha256=bad9dc0a68dd1c047982c85f13192a8759c16298f592785f18db1d8f74971007
u_boot_item_sha256=dfc59bbf7e4fe66f0ab2014fbe83e19ea7074a09e5c9c3740ee77fd77c51f89f
selector_bmp_sha256=bc3dcbd5a046168fe3b463b66da96cddafd84c0779c804f308b5d788c46bcb03
selector_bmp=file: PC bitmap, Windows 3.x format, 320 x 240 x 24, cbSize 230454
backup=/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260702T234205Z.bin
backup_sha256=9fabc67f143b3aa5e15ad17368684e5597196555891c886e92fc17a60ca2a4ec
```

The installed bytes were read back from `/dev/mmcblk1` at `bs=8192 skip=2050`
and matched the candidate for the exact 1388544-byte package length.

The 2026-07-03 diagnostic candidate uses the same script-first bootmenu U-Boot
and embedded selector logo, plus `sunxi_drm_env` for pre-kernel display-state
capture:

```text
device=/dev/mmcblk1
package=/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu-scriptfirst-selector-logo-drm-env.fex
package_sha256=fd0222a54312c8c20c26f99509ec466ed1afd2fef34ca3f56071d2f4c97731e2
u_boot_item_sha256=cca39d1ef71be8a3f94f719f6265a8813248c299a8546289078143e9cd0f4ed7
selector_bmp_sha256=bc3dcbd5a046168fe3b463b66da96cddafd84c0779c804f308b5d788c46bcb03
selector_bmp=file: PC bitmap, Windows 3.x format, 320 x 240 x 24, cbSize 230454
backup=/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T010004Z.bin
backup_sha256=74f1cffbafe1c14c5a6ff6e410a73b3b51bb08f678fb151c806d8ff781209bef
```

This package has been inspected, installed to `/dev/mmcblk1`, and verified by
reading the package slot back from SD.

The 2026-07-03 framebuffer-test diagnostic candidate adds `sunxi_drm fbtest`.
It keeps the same script-first bootmenu, embedded selector logo, native
`1024x600` HDMI fallback, and `sunxi_drm_env` diagnostic. The new command
enables the vendor DRM framebuffer path and paints color bars directly into
the active framebuffer:

```text
device=/dev/mmcblk1
package=/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu-scriptfirst-selector-logo-drm-env-1024x600-fbtest.fex
package_sha256=831fad7f31e02c3fe099c2e83402ffc207d93ce2fe41272cb26fb8758fe9a2a0
u_boot_item_sha256=472dd23358166ac1730513bcba60ec8606dba92d8ae87456bde61f851c5a5ae8
selector_bmp_sha256=bc3dcbd5a046168fe3b463b66da96cddafd84c0779c804f308b5d788c46bcb03
backup=/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T011715Z.bin
backup_sha256=d44158d530b844a15b7420fa22404ae7a4c1ce8005b42b4c260510dbe4e84f3f
```

This package has been inspected, installed to `/dev/mmcblk1`, and verified by
reading the package slot back from SD.

The 2026-07-03 native-mode diagnostic candidate changes the vendor HDMI
fallback to `1024x600` using the Linux/Xorg modeline and keeps the same
script-first bootmenu, embedded selector logo, and `sunxi_drm_env` diagnostic:

```text
device=/dev/mmcblk1
package=/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu-scriptfirst-selector-logo-drm-env-1024x600.fex
package_sha256=79034667cf71181c620568607fa085c7eb551a026a208992e2a310bc0d0f1647
u_boot_item_sha256=ac4c20b765e56427e27cad48e069ebee34ad3ae7f9fbf6b71e67cc747ff2b12e
selector_bmp_sha256=bc3dcbd5a046168fe3b463b66da96cddafd84c0779c804f308b5d788c46bcb03
backup=/var/cache/orangepi4pro-images/bootloader-backups/mmcblk1-bootloader-before-20260703T010829Z.bin
backup_sha256=12ba9643679371de85327ca0a4019911a5190cb18def9832b07c30932c20c2cc
```

This package has been inspected, installed to `/dev/mmcblk1`, and verified by
reading the package slot back from SD.

The installed platform script shows the vendor package write locations:

```text
boot0_sdcard.fex        -> device, bs=8k seek=1
boot_package.fex        -> device, bs=8k seek=2050
boot0_spinor_a733.fex   -> /dev/mtd0 offset 0
boot_package_a733_nvme.fex -> /dev/mtd0 offset 262144
```

Do not write boot0, NVMe boot sectors, SPI/MTD, partitions, filesystems, or
firmware for boot-selector tests. Keep the SD card recoverable because it is
still the active firmware source.
