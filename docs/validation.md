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

