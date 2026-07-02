# Board Support Install Notes

Future Ubuntu/Kali M.2 installs need:

- Kernel with the config in `configs/kernel/orangepi4pro-cyberdeck.fragment`.
- Orange Pi 4 Pro A733 DTB matching the selected kernel tree.
- Boot assets compatible with stock/vendor U-Boot first.
- `qdtech-touch-x11` installed only when native HID multitouch fails.

Install scripts should be run inside a mounted target rootfs, not against the
live SD root by accident. The current session provides dry-run helpers only.

