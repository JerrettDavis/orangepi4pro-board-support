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

The next file-only candidate uses the same script-first bootmenu U-Boot plus an
embedded selector logo generated at build time:

```text
package=/var/cache/orangepi4pro-images/build/boot-package-candidates/boot_package_sd-bootmenu-scriptfirst-selector-logo.fex
package_sha256=bad9dc0a68dd1c047982c85f13192a8759c16298f592785f18db1d8f74971007
u_boot_item_sha256=dfc59bbf7e4fe66f0ab2014fbe83e19ea7074a09e5c9c3740ee77fd77c51f89f
selector_bmp_sha256=bc3dcbd5a046168fe3b463b66da96cddafd84c0779c804f308b5d788c46bcb03
selector_bmp=file: PC bitmap, Windows 3.x format, 320 x 240 x 24, cbSize 230454
```

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
