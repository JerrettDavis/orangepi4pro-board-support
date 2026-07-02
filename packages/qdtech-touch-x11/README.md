# Orange Pi 4 Pro + Hosyond/QDtech MPI7003 Touch Fix

This bundle makes the Hosyond/QDtech MPI7003 USB touchscreen usable on the
current Orange Pi 4 Pro Xorg image and is intended to be copied into future
Ubuntu/Kali/Arch installs on the M.2 disk.

## Why this is needed

The current kernel reports:

- `CONFIG_HID_MULTITOUCH` is not set
- `CONFIG_HIDRAW` is not set
- `CONFIG_UHID` is not set

Because of that, `hid-generic` exposes a broken evdev touchscreen that pins
absolute coordinates at `1024,600`. The USB controller itself works; raw USB
reports contain real coordinates in report ID `0x01`:

- byte 1: touch state
- bytes 3-4: little-endian X
- bytes 5-6: little-endian Y

`qdtech-touch-x11` detaches the broken kernel HID binding, reads endpoint
`0x82` directly with libusb, and injects corrected pointer events into Xorg
through XTest.

## Install

From this directory:

```bash
sudo apt-get install -y build-essential libusb-1.0-0-dev libx11-dev libxtst-dev
gcc -O2 -Wall -Wextra -o bin/qdtech-touch-x11 bin/qdtech-touch-x11.c -lusb-1.0 -lX11 -lXtst
gcc -O2 -Wall -Wextra -o bin/qdtech-usb-dump bin/qdtech-usb-dump.c -lusb-1.0
sudo bin/install-touchscreen-xorg-fix
sudo udevadm control --reload-rules
```

Log out/in or reboot. The X11 bridge autostarts from:

`/home/orangepi/.config/autostart/qdtech-touch-x11.desktop`

## Calibration

Default calibration is stored in `/etc/qdtech-touch-x11.conf`:

```text
MIN_X=22
MAX_X=994
MIN_Y=-5
MAX_Y=544
```

Observed useful points from the first raw capture:

- top-left: around `76,73`
- top-right: around `968,62`
- center: around `513,327`
- bottom-left: around `125,472`
- bottom-right: around `916,487`

If edges need stretching, adjust the min/max values and restart the bridge.

## Future OS Notes

Prefer a kernel with `CONFIG_HID_MULTITOUCH=y` or `m`, `CONFIG_HIDRAW=y`, and
`CONFIG_INPUT_UINPUT=y`. With those enabled, the standard Linux input stack can
replace this X11 bridge. Until then, this bundle is the portable compatibility
shim for Xorg-based installs.
