#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成「局域网控制 DSH」的应用图标源图（1024px 正方形）。

图形语义：
  - 一块显示器 = 被控的电脑（跑着 DSH）
  - 屏幕里的 `>_` = 终端 / 命令行
  - 右上角的信号弧 = 局域网无线连接
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 1024

BG_TOP = (10, 16, 32)
BG_BOTTOM = (30, 42, 104)
STROKE = (109, 135, 255)      # 霓虹蓝
ACCENT = (0, 229, 255)        # 青
GLOW = (77, 107, 254)


def gradient(size, c1, c2):
    img = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / max(1, size - 1)
        c = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (255,)
        d.line([(0, y), (size, y)], fill=c)
    return img


def rounded_monitor(draw, box, radius, width, color):
    x0, y0, x1, y1 = box
    draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, outline=color, width=width)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "new_icon.png"

    img = gradient(S, BG_TOP, BG_BOTTOM)

    # 背景柔光，避免纯色死板
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    hd.ellipse([S * 0.16, S * 0.10, S * 0.86, S * 0.80], fill=GLOW + (46,))
    halo = halo.filter(ImageFilter.GaussianBlur(S * 0.09))
    img = Image.alpha_composite(img, halo)

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # 显示器外框
    box = (S * 0.19, S * 0.26, S * 0.81, S * 0.66)
    rounded_monitor(d, box, radius=S * 0.045, width=int(S * 0.030), color=STROKE + (255,))

    # 支架
    d.line([(S * 0.50, S * 0.66), (S * 0.50, S * 0.725)], fill=STROKE + (255,), width=int(S * 0.030))
    d.line([(S * 0.385, S * 0.735), (S * 0.615, S * 0.735)], fill=STROKE + (255,), width=int(S * 0.030))

    # 终端提示符 ">_"
    w = int(S * 0.030)
    d.line([(S * 0.315, S * 0.375), (S * 0.405, S * 0.455)], fill=ACCENT + (255,), width=w)
    d.line([(S * 0.405, S * 0.455), (S * 0.315, S * 0.535)], fill=ACCENT + (255,), width=w)
    d.line([(S * 0.445, S * 0.535), (S * 0.565, S * 0.535)], fill=ACCENT + (255,), width=w)

    # 局域网信号弧（右上角，三道）
    cx, cy = S * 0.795, S * 0.185
    for i, (r, a) in enumerate([(0.075, 235), (0.115, 190), (0.155, 145)]):
        rr = S * r
        start, end = -105, -15
        d.arc([cx - rr, cy - rr, cx + rr, cy + rr], start=start, end=end,
              fill=ACCENT + (a,), width=int(S * 0.024))

    # 发光
    glow = layer.filter(ImageFilter.GaussianBlur(S * 0.012))
    img = Image.alpha_composite(img, glow)
    img = Image.alpha_composite(img, layer)

    img.save(out, "PNG")
    print(f"icon written: {os.path.abspath(out)}")


if __name__ == "__main__":
    main()
