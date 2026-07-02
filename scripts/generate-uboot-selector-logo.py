#!/usr/bin/env python3
"""Generate the vendor U-Boot embedded boot_bmp.h selector image."""

from __future__ import annotations

import argparse
import gzip
import io
import pathlib
import textwrap


def load_pillow():
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError as exc:  # pragma: no cover - depends on host packages
        raise SystemExit(
            "ERROR: python3 PIL/Pillow is required; install python3-pil"
        ) from exc
    return Image, ImageDraw, ImageFont


def font(ImageFont, name: str, size: int):
    for path in (
        f"/usr/share/fonts/truetype/dejavu/{name}.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def draw_logo() -> bytes:
    Image, ImageDraw, ImageFont = load_pillow()
    img = Image.new("RGB", (320, 240), (7, 9, 13))
    draw = ImageDraw.Draw(img)

    title = font(ImageFont, "DejaVuSans-Bold", 20)
    body = font(ImageFont, "DejaVuSans", 14)
    body_bold = font(ImageFont, "DejaVuSans-Bold", 14)
    small = font(ImageFont, "DejaVuSans", 11)

    orange = (239, 128, 37)
    white = (236, 242, 247)
    muted = (158, 170, 181)
    line = (58, 67, 78)
    selected = (25, 40, 50)

    draw.rectangle((0, 0, 319, 239), fill=(7, 9, 13))
    draw.rectangle((0, 0, 319, 8), fill=orange)
    draw.text((16, 22), "Orange Pi 4 Pro", fill=(255, 186, 84), font=title)
    draw.text((16, 50), "Cyberdeck Boot Selector", fill=white, font=body_bold)
    draw.line((16, 76, 304, 76), fill=line, width=1)

    draw.rounded_rectangle((18, 90, 302, 118), radius=4, fill=selected, outline=(70, 95, 108))
    draw.text((28, 96), "Ubuntu NVMe - cyberdeck kernel", fill=white, font=body)
    draw.text((28, 127), "Ubuntu SD - stock kernel", fill=white, font=body)
    draw.text((28, 154), "Ubuntu NVMe - verbose boot", fill=white, font=body)

    draw.line((16, 184, 304, 184), fill=line, width=1)
    draw.text((16, 195), "Use USB keyboard arrows + Enter", fill=muted, font=small)
    draw.text((16, 212), "Default boots NVMe after 10 seconds", fill=muted, font=small)

    out = io.BytesIO()
    img.save(out, "BMP")
    return out.getvalue()


def c_array(data: bytes) -> str:
    lines = []
    for offset in range(0, len(data), 12):
        chunk = data[offset : offset + 12]
        lines.append("  " + ", ".join(f"0x{byte:02x}" for byte in chunk) + ",")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--bmp-output", type=pathlib.Path)
    args = parser.parse_args()

    bmp = draw_logo()
    gz = gzip.compress(bmp, compresslevel=9, mtime=0)

    if len(bmp) > 256 * 1024:
        raise SystemExit(f"ERROR: BMP is too large for U-Boot buffer: {len(bmp)}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        textwrap.dedent(
            f"""\
            unsigned char boot_bmp_gz[] = {{
            {c_array(gz)}
            }};
            unsigned int boot_bmp_gz_len = {len(gz)};
            """
        ),
        encoding="ascii",
    )
    if args.bmp_output:
        args.bmp_output.parent.mkdir(parents=True, exist_ok=True)
        args.bmp_output.write_bytes(bmp)

    print(f"wrote {args.output}")
    print(f"bmp_size={len(bmp)}")
    print(f"gzip_size={len(gz)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
