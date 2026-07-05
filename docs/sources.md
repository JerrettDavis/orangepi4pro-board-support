# Source Manifest

See `../orangepi4pro-cyberdeck/docs/sources.md` for the full cross-repo source
manifest. Board-support-specific pins verified 2026-07-02:

| Source | URL | Branch | Commit |
| --- | --- | --- | --- |
| Vendor Linux 6.6 BSP | https://github.com/orangepi-xunlong/linux-orangepi.git | `orange-pi-6.6-sun60iw2` | `8a9be72c9006a87f786736b3aa4e2dfd971c1429` |
| Vendor Linux 5.15 BSP | https://github.com/orangepi-xunlong/linux-orangepi.git | `orange-pi-5.15-sun60iw2` | `3de7a14a69f9e1fcbfec914c972a5398f0abd6d9` |
| Vendor U-Boot BSP | https://github.com/orangepi-xunlong/u-boot-orangepi.git | `v2018.05-sun60iw2` | `b791be842935b27268ae3d00e943a9075495f30a` |
| NVMe Gen1 workaround | https://github.com/CarterPerez-dev/orangepi-4-pro-nvme-fix.git | `main` | `fe4c31ec0115d3f2493905be07426f36f666aab5` |
| Official Orange Pi build system | https://github.com/orangepi-xunlong/orangepi-build.git | `main` | `bdba421984211da19191dc6ac6818a247817335f` |
| sun60iw2 package payloads | https://gitee.com/orangepi-xunlong/sun60iw2_packages.git | `sun60iw2_packages` | `28961f4804cf8c2826b4e560c76bd5239658e90b` |

Official image/recovery source notes verified 2026-07-05:

- Orange Pi 4 Pro official Google Drive folder:
  `https://drive.google.com/drive/folders/1AzF-uTwA328qDFPaVBaKpiP4VjZjkmbS`
- Visible 1.0.6 image archive IDs in that folder:
  - `1MoYKSZtDrBkunJeHwLh7NM09IFFjLWoJ`:
    `Orangepi4pro_1.0.6_debian_bookworm_desktop_xfce_linux5.15.147.7z`
  - `1CYfOaY6f5DozJBNvPJ0Gx1jBIFlGe8fn`:
    `Orangepi4pro_1.0.6_debian_bookworm_server_linux5.15.147.7z`
  - `1STIstXaNl46k_dydFJ4aRn2QwFRvD3SZ`:
    `Orangepi4pro_1.0.6_debian_bullseye_desktop_xfce_linux5.15.147.7z`
  - `1jgdsDIVKfR-dWRON3lLGW43vrC34Ny1x`:
    `Orangepi4pro_1.0.6_debian_bullseye_server_linux5.15.147.7z`
- Official Google Drive backup folder:
  `https://drive.google.com/drive/folders/1Oyj6_u-CH7-wb15mWc_NL-GQRDWNhiRP`
- Visible 1.0.4 backup archive IDs:
  - `1dCtOnRh4i6AZqJE9RgWW9aZ1V5UmK6v1`:
    `Orangepi4pro_1.0.4_debian_bookworm_desktop_xfce_linux5.15.147.7z`
  - `1B21QBrrusEZRyTzZktXsc6e_klcv64y6`:
    `Orangepi4pro_1.0.4_debian_bullseye_desktop_xfce_linux5.15.147.7z`
- Direct download attempts for the 1.0.6 Bullseye server and 1.0.4 Bullseye
  desktop archives returned Google Drive quota-exceeded HTML on 2026-07-05.
  No valid official image archive was downloaded in that pass.
- The official `sun60iw2_packages` repo contains rootfs/NPU/media packages,
  but no `LogoRegData.bin`, boot-resource image, or bootloader logo register
  table.

Vendor U-Boot build validation on this board produced `u-boot.bin` and
`u-boot-sun60iw2p1.bin` from `sun60iw2p1_t736_defconfig`. The shipped
`scripts/sunxi_ubootools` helper is not executable on the ARM host. The
installed `boot_package*.fex` files were identified as Allwinner TOC1 packages
using magic `0x89119800` and checksum stamp `0x5f0a6c39`; see
`vendor-u-boot-bootmenu.md` for the parser/repacker workflow.
