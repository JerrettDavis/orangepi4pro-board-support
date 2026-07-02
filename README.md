# Orange Pi 4 Pro Board Support

Board support files for the Allwinner A733 / sun60iw2 Orange Pi 4 Pro.

This repo tracks kernel config fragments, DTS patch workflow notes, touch and
display fallback support, and validation helpers. It intentionally avoids
committing large vendor source trees or binary images.

## Contents

- `configs/kernel/orangepi4pro-cyberdeck.fragment`: required kernel options.
- `configs/dts/`: DTS patch workflow and optional NVMe Gen1 notes.
- `packages/qdtech-touch-x11/`: current X11/libusb touch fallback copied from
  `/home/orangepi/touchscreen-fix-src`.
- `scripts/`: dry-run board support validation and capture helpers.

## Kernel Direction

The first bootable target is the vendor 5.15 sun60iw2 BSP because it matches
the current Orange Pi firmware and legacy `bootm` flow. After that kernel is
confirmed on NVMe with native HID touch, this repo should become the clean
board-support source for:

- a maintained 5.15 cyberdeck branch for recovery and regression checks;
- a 6.x+ kernel fork once boot, display, PCIe/NVMe, USB HID, and touch behavior
  are understood on the known-good 5.15 baseline;
- board DTS/DTSI work for `xunlong,orangepi-4-pro` / `arm,sun60iw2p1`;
- reusable config fragments for Ubuntu, Kali, Yocto, and future images.

## Current Touch Status

The stock `5.15.147-sun60iw2` kernel lacks `CONFIG_HID_MULTITOUCH`,
`CONFIG_HIDRAW`, `CONFIG_UHID`, and `CONFIG_INPUT_UINPUT`. Until a better
kernel is built, the QDtech/Specialix MPI7003 touchscreen is handled by the
X11/libusb bridge in `packages/qdtech-touch-x11`.
