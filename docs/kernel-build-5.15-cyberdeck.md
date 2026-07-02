# Cyberdeck Kernel Build: 5.15 Vendor BSP

Prepared on 2026-07-02 for the Orange Pi 4 Pro A733 / sun60iw2 board.

## Source

- Repository: `https://github.com/orangepi-xunlong/linux-orangepi.git`
- Branch: `orange-pi-5.15-sun60iw2`
- Commit: `3de7a14a69f9e1fcbfec914c972a5398f0abd6d9`
- Local checkout: `/mnt/orangepi4pro-m2/images-cache/linux-orangepi-5.15-sun60iw2`

## Kernel Release

```text
5.15.147-sun60iw2-cyberdeck
```

The build used the stock `/boot/config-5.15.147-sun60iw2` as the base config,
then enabled the cyberdeck fragment requirements.

Key native touch/input options:

```text
CONFIG_HID_MULTITOUCH=m
CONFIG_HIDRAW=y
CONFIG_UHID=m
CONFIG_INPUT_MISC=y
CONFIG_INPUT_UINPUT=m
CONFIG_INPUT_EVDEV=y
CONFIG_USB_HID=y
```

Other target-critical options:

```text
CONFIG_NVME_CORE=y
CONFIG_BLK_DEV_NVME=y
CONFIG_OVERLAY_FS=y
CONFIG_IKCONFIG=y
CONFIG_IKCONFIG_PROC=y
```

## Build Commands

```bash
make ARCH=arm64 LOCALVERSION= olddefconfig
make -j6 ARCH=arm64 LOCALVERSION= Image modules dtbs
make ARCH=arm64 LOCALVERSION= kernelrelease
```

`LOCALVERSION=` is deliberate here. The configured local version already
contains `-sun60iw2-cyberdeck`, and passing an empty make-time local version
prevents a dirty-tree `+` suffix.

## Installed Target

Modules were installed into the NVMe Ubuntu root only:

```bash
make ARCH=arm64 LOCALVERSION= \
  INSTALL_MOD_PATH=/mnt/orangepi4pro-m2/ubuntu-root \
  modules_install
```

No SD boot partition, SPI flash, MTD device, or bootloader sector was changed.

Offline module validation:

```bash
chroot /mnt/orangepi4pro-m2/ubuntu-root \
  modinfo -k 5.15.147-sun60iw2-cyberdeck \
  hid-multitouch uhid uinput
```
