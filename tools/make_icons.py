#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把一张方形源图 (new_icon.png) 生成 Android 全套图标：

  1. 传统图标  mipmap-*/ic_launcher.png        (48/72/96/144/192, 圆角方形)
  2. 圆形图标  mipmap-*/ic_launcher_round.png  (同上尺寸, 圆形裁切)
  3. 自适应前景 mipmap-*/ic_launcher_foreground.png
                 (108dp 画布, 图形缩到 62% 落在 72dp 安全区内)
  4. 自适应定义 mipmap-anydpi-v26/ic_launcher.xml + ic_launcher_round.xml
     (背景用 @color/ic_launcher_background, 前景用上面的 png)

用法:
    python tools/make_icons.py 路径\new_icon.png
    python tools/make_icons.py 路径\new_icon.png --preview   # 额外输出预览拼图
"""

import argparse
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    sys.exit("缺少 Pillow，请先执行: pip install pillow")

# Android 各密度：传统图标边长 / 自适应 108dp 画布边长
DENSITIES = {
    "mdpi":    (48, 108),
    "hdpi":    (72, 162),
    "xhdpi":   (96, 216),
    "xxhdpi":  (144, 324),
    "xxxhdpi": (192, 432),
}

# 自适应图标安全区：内容应落在中心 72/108 的圆内，这里取 0.62 留边
ADAPTIVE_CONTENT_RATIO = 0.62
# 传统图标内容占比（留一点内边距更好看）
LEGACY_CONTENT_RATIO = 0.86
CORNER_RADIUS_RATIO = 0.22

BG_COLOR = (11, 18, 32, 255)  # #0B1220，与 brand_deep 一致


def load_source(path: str) -> Image.Image:
    if not os.path.isfile(path):
        sys.exit(f"找不到源图: {path}")
    img = Image.open(path)
    img.load()
    if img.mode not in ("RGBA", "RGB"):
        img = img.convert("RGBA")
    elif img.mode == "RGB":
        img = img.convert("RGBA")
    w, h = img.size
    if w != h:
        s = min(w, h)
        left = (w - s) // 2
        top = (h - s) // 2
        img = img.crop((left, top, left + s, top + s))
        print(f"  · 源图非正方形，已居中裁切为 {s}x{s}")
    if img.size[0] < 432:
        print(f"  ! 源图只有 {img.size[0]}px，建议用 >= 512px 的图，否则大图标会发虚")
    return img


def scaled(img: Image.Image, canvas: int, ratio: float) -> Image.Image:
    """把 img 等比缩放到 canvas*ratio，居中贴到透明 canvas 上。"""
    canvas_img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    side = max(1, int(round(canvas * ratio)))
    art = img.resize((side, side), Image.LANCZOS)
    off = (canvas - side) // 2
    canvas_img.paste(art, (off, off), art)
    return canvas_img


def rounded_mask(size: int, radius_ratio: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    r = int(size * radius_ratio)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    return mask


def circle_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([0, 0, size - 1, size - 1], fill=255)
    return mask


def legacy_icon(src: Image.Image, size: int, circular: bool) -> Image.Image:
    """传统图标：品牌色底 + 居中图形，圆角方形或圆形。"""
    base = Image.new("RGBA", (size, size), BG_COLOR)
    art = scaled(src, size, LEGACY_CONTENT_RATIO)
    base = Image.alpha_composite(base, art)
    mask = circle_mask(size) if circular else rounded_mask(size, CORNER_RADIUS_RATIO)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(base, (0, 0), mask)
    return out


ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", help="方形源图路径，例如 new_icon.png")
    ap.add_argument("--res", default=None, help="res 目录，默认自动定位到 app/src/main/res")
    ap.add_argument("--preview", action="store_true", help="额外生成预览拼图")
    args = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    res = args.res or os.path.join(os.path.dirname(here), "app", "src", "main", "res")
    if not os.path.isdir(res):
        sys.exit(f"找不到 res 目录: {res}")

    print(f"源图: {args.source}")
    src = load_source(args.source)

    for density, (legacy, adaptive) in DENSITIES.items():
        out_dir = os.path.join(res, f"mipmap-{density}")
        os.makedirs(out_dir, exist_ok=True)

        legacy_icon(src, legacy, circular=False).save(
            os.path.join(out_dir, "ic_launcher.png"), "PNG", optimize=True)
        legacy_icon(src, legacy, circular=True).save(
            os.path.join(out_dir, "ic_launcher_round.png"), "PNG", optimize=True)
        scaled(src, adaptive, ADAPTIVE_CONTENT_RATIO).save(
            os.path.join(out_dir, "ic_launcher_foreground.png"), "PNG", optimize=True)
        print(f"  + mipmap-{density}: {legacy}px 传统/圆形 + {adaptive}px 自适应前景")

    anydpi = os.path.join(res, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(os.path.join(anydpi, name), "w", encoding="utf-8") as f:
            f.write(ADAPTIVE_XML)
    print(f"  + mipmap-anydpi-v26: ic_launcher.xml / ic_launcher_round.xml (Adaptive Icon)")

    if args.preview:
        tile = 256
        sheet = Image.new("RGBA", (tile * 4, tile), (245, 245, 245, 255))
        samples = [
            legacy_icon(src, tile, False),
            legacy_icon(src, tile, True),
            scaled(src, tile, ADAPTIVE_CONTENT_RATIO),
        ]
        # 模拟自适应裁切（圆形遮罩）
        clipped = Image.new("RGBA", (tile, tile), BG_COLOR)
        clipped = Image.alpha_composite(clipped, samples[2])
        clip_mask = circle_mask(tile)
        clipped.putalpha(clip_mask)
        samples.append(clipped)
        for i, im in enumerate(samples):
            sheet.alpha_composite(im, (i * tile, 0))
        out = os.path.join(here, "icon_preview.png")
        sheet.save(out, "PNG")
        print(f"  + 预览: {out}")

    print("完成。")


if __name__ == "__main__":
    main()
