# Changelog

## 0.1.0 - 2026-07-02

- Created board-support repo.
- Added QDtech MPI7003 X11/libusb fallback source.
- Added kernel config fragment for native HID multitouch, HIDRAW, UHID,
  UINPUT, NVMe, overlayfs, TUN, and common USB input support.
- Documented the vendor 5.15 cyberdeck kernel build baseline.
- Added CI checks, including compilation of the touch helper C sources.

## Unreleased

- Added a U-Boot HDMI TOP PHY auto-calculation patch that ports the Linux
  sun60iw2 PLL selection path, allowing the 1024x600 / 49 MHz cyberdeck mode to
  use the same `0xE8193000` TOP PHY PLL value Linux uses after HDMI becomes
  visible.
- Added TOP PHY PLL register fields to U-Boot HDMI diagnostics so bootargs can
  prove whether pre-OS HDMI programmed the same registers as visible Linux.
- Added a U-Boot HDMI reinit stage diagnostic patch that records the real
  disable, mode-set, TCON init, clock-rate, HDMI config, TOP PHY, and
  DesignWare core state for the pre-OS HDMI pattern test.
- Added a U-Boot DRM reinit diagnostic command that reruns full display
  disable/init/enable before the HDMI pattern test.
