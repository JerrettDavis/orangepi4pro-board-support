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

## Menu Fragment

`configs/u-boot/orangepi4pro-bootmenu.fragment` enables:

- `CONFIG_CMD_BOOTMENU=y`
- `CONFIG_AUTOBOOT_MENU_SHOW=y`
- `CONFIG_USB_KEYBOARD=y`
- `CONFIG_SYS_USB_EVENT_POLL=y`
- `CONFIG_DM_KEYBOARD=y`
- `# CONFIG_EFI_LOADER is not set`

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

## Flashing Status

Do not flash these artifacts yet. The installed platform script shows the
current vendor package writes:

```text
boot0_sdcard.fex        -> device, bs=8k seek=1
boot_package.fex        -> device, bs=8k seek=2050
boot0_spinor_a733.fex   -> /dev/mtd0 offset 0
boot_package_a733_nvme.fex -> /dev/mtd0 offset 262144
```

Do not flash generated packages until they pass all local validation checks.
A safe test plan should use a separate recovery/test SD when possible, or a
verified package rebuild with a byte-for-byte stock rebuild check and a saved
rollback copy, then keep the current NVMe and SD boot media recoverable.
