#!/usr/bin/env python3
"""
توليد أيقونات التطبيق (Adaptive Icon) من الملف المصدر assets/icon/icon_source.png.

الناتج:
  android/app/src/main/res/mipmap-*/ic_launcher.png            أيقونة قديمة بمCorners مدوّرة
  android/app/src/main/res/mipmap-*/ic_launcher_round.png      أيقونة دائرية
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png الطبقة الأمامية (Adaptive)
  android/app/src/main/res/mipmap-*/ic_launcher_background.png طبقة الخلفية
  android/app/src/main/res/mipmap-*/ic_launcher_monochrome.png طبقة الأيقونة أحادية اللون

التشغيل:  python3 tool/generate_icons.py
"""

from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "icon" / "icon_source.png"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

# مقاسات mipmap القياسية: الاسم -> (أيقونة قديمة, foreground/background/monochrome)
DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

ADAPTIVE_FACTOR = 108 / 48  # طبقة Adaptive icon أكبر بمقدار 2.25
BG_COLOR = (5, 7, 10, 255)
RED = (239, 68, 68)


def load_source() -> Image.Image:
    if not SOURCE.exists():
        raise SystemExit(f"الملف المصدر غير موجود: {SOURCE}")
    return Image.open(SOURCE).convert("RGBA")


def symbol_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    """إيجاد حدود الرمز الأحمر داخل الصورة."""
    width, height = image.size
    pixels = image.load()
    min_x, min_y, max_x, max_y = width, height, 0, 0
    for y in range(0, height, 2):
        for x in range(0, width, 2):
            r, g, b, _ = pixels[x, y]
            if r > 80 and r > g * 1.35 and r > b * 1.35:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if max_x <= min_x or max_y <= min_y:
        return (0, 0, width, height)
    return (min_x, min_y, max_x, max_y)


def rounded_mask(size: int, radius_ratio: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    radius = int(size * radius_ratio)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def circular_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, size - 1, size - 1), fill=255)
    return mask


def make_legacy(source: Image.Image, size: int, round_icon: bool) -> Image.Image:
    resized = source.resize((size, size), Image.LANCZOS)
    mask = circular_mask(size) if round_icon else rounded_mask(size, 0.22)
    resized.putalpha(mask)
    return resized


def make_background(size: int) -> Image.Image:
    """خلفية داكنة مع توهج أحمر خفيف في المنتصف."""
    background = Image.new("RGBA", (size, size), BG_COLOR)
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    radius = int(size * 0.30)
    draw.ellipse(
        (size // 2 - radius, size // 2 - radius, size // 2 + radius, size // 2 + radius),
        fill=(*RED, 70),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(radius / 2))
    return Image.alpha_composite(background, glow)


def make_foreground(source: Image.Image, size: int) -> Image.Image:
    """طبقة أمامية شفافة تحمل الرمز داخل المنطقة الآمنة (≈58% من الحجم)."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    box = symbol_bbox(source)
    symbol = source.crop(box)

    target = int(size * 0.58)
    ratio = target / max(symbol.width, symbol.height)
    new_size = (max(1, int(symbol.width * ratio)), max(1, int(symbol.height * ratio)))
    symbol = symbol.resize(new_size, Image.LANCZOS)

    offset = ((size - new_size[0]) // 2, (size - new_size[1]) // 2)
    canvas.alpha_composite(symbol, offset)
    return canvas


def make_monochrome(source: Image.Image, size: int) -> Image.Image:
    """الرمز بالأبيض على خلفية شفافة للأيقونات النظامية (API 33+)."""
    foreground = make_foreground(source, size)
    alpha = foreground.getchannel("A")
    mono = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    mono.putalpha(alpha)
    return mono


def main() -> None:
    source = load_source()
    print(f"المصدر: {source} ({source.width}x{source.height})")

    for density, base in DENSITIES.items():
        folder = RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)

        make_legacy(source, base, round_icon=False).save(folder / "ic_launcher.png")
        make_legacy(source, base, round_icon=True).save(folder / "ic_launcher_round.png")

        adaptive = int(base * ADAPTIVE_FACTOR)
        make_foreground(source, adaptive).save(folder / "ic_launcher_foreground.png")
        make_background(adaptive).save(folder / "ic_launcher_background.png")
        make_monochrome(source, adaptive).save(folder / "ic_launcher_monochrome.png")

        print(f"  mipmap-{density}: {base}px (adaptive {adaptive}px)")

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
        "</adaptive-icon>\n"
    )
    (anydpi / "ic_launcher.xml").write_text(xml, encoding="utf-8")
    (anydpi / "ic_launcher_round.xml").write_text(xml, encoding="utf-8")
    print("  mipmap-anydpi-v26: ic_launcher.xml, ic_launcher_round.xml")


if __name__ == "__main__":
    main()
