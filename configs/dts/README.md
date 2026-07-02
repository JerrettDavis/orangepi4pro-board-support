# DTS Patch Workflow

Use source DTS patches only.

1. Identify the DTS for Orange Pi 4 Pro in the selected kernel tree.
2. Compare it against the current stock DTB decompile from
   `/boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb`.
3. Carry minimal patches for HDMI, USB, PCIe/NVMe, regulators, Wi-Fi/Bluetooth,
   LEDs, thermal zones, and input devices.
4. If the Fanxiang S500Pro shows NVMe link resets, evaluate the community
   Gen1 workaround before applying it.

Never commit hand-edited DTB binaries.

