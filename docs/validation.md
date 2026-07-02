# Board Validation

Run:

```bash
scripts/validate-board-support.sh
```

Validation should confirm:

- Board compatible strings are correct.
- NVMe is present and not reset-looping in `dmesg`.
- Required kernel options are enabled or documented as missing.
- HDMI/X11 display state is captured when a graphical session exists.
- QDtech touch fallback is present if native HID multitouch is missing.

After booting the NVMe cyberdeck kernel, confirm native touch/input:

```bash
uname -r
zgrep -E 'CONFIG_(HID_MULTITOUCH|HIDRAW|UHID|INPUT_UINPUT|INPUT_EVDEV|USB_HID)=' /proc/config.gz
lsmod | grep -E 'hid_multitouch|uhid|uinput'
libinput list-devices
sudo evtest
```

Expected kernel release:

```text
5.15.147-sun60iw2-cyberdeck
```
