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

## Current Touch Status

The stock `5.15.147-sun60iw2` kernel lacks `CONFIG_HID_MULTITOUCH`,
`CONFIG_HIDRAW`, `CONFIG_UHID`, and `CONFIG_INPUT_UINPUT`. Until a better
kernel is built, the QDtech/Specialix MPI7003 touchscreen is handled by the
X11/libusb bridge in `packages/qdtech-touch-x11`.

