#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成占位图标（等你提供 new_icon.png 后会被 apply_icon.ps1 覆盖）。"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

S = 1024
BG1 = (8, 14, 28)
BG2 = (24, 32, 96)
NEON = (77, 107, 254)
NEON2 = (0, 229, 255)


def vertical_gradient(size, c1, c2):
    img = Image.new("RGBA", (size, size))
    for y in range(size):
        t = y / max(1, size - 1)
        c = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (255,)
        ImageDraw.Draw(img).line([(0, y), (size, y)], fill=c)
    return img


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "new_icon.png"
    img = vertical_gradient(S, BG1, BG2)

    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([S * 0.10, S * 0.10, S * 0.90, S * 0.90], outline=NEON + (255,), width=int(S * 0.035))
    glow = glow.filter(__import__("PIL.ImageFilter", fromlist=["ImageFilter"]).GaussianBlur(S * 0.02))
    img = Image.alpha_composite(img, glow)

    d = ImageDraw.Draw(img)
    d.ellipse([S * 0.10, S * 0.10, S * 0.90, S * 0.90], outline=NEON2 + (220,), width=int(S * 0.012))

    font = None
    size = int(S * 0.40)
    for path in (r"C:\Windows\Fonts\msyhbd.ttc", r"C:\Windows\Fonts\msyh.ttc",
                 r"C:\Windows\Fonts\simhei.ttf"):
        if os.path.isfile(path):
            try:
                font = ImageFont.truetype(path, size)
                break
            except Exception:
                continue
    if font is None:
        sys.exit("找不到中文字体")
    text = "赛"
    box = d.textbbox((0, 0), text, font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    d.text(((S - tw) / 2 - box[0], (S - th) / 2 - box[1]), text, font=font, fill=(255, 255, 255, 255))

    img.save(out, "PNG")
    print(f"占位图标已生成: {os.path.abspath(out)}")


if __name__ == "__main__":
    main()
