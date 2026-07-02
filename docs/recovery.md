# Recovery Notes

Board support changes must remain recoverable from the current SD image.

- Keep the touch fallback installable but optional.
- Keep DTS changes as source patches only; do not hand-edit DTB binaries.
- Capture the current DTB before kernel experiments:

```bash
mkdir -p research/private/current-boot
cp -a /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb research/private/current-boot/
dtc -I dtb -O dts -o research/private/current-boot/sun60i-a733-orangepi-4-pro.dts /boot/dtb/allwinner/sun60i-a733-orangepi-4-pro.dtb
```

Do not commit private captures unless their provenance and licensing are clear.

