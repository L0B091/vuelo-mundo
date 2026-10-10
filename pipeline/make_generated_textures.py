#!/usr/bin/env python3
"""Texturas generadas por el proyecto (obra propia, CC0): fronda de palmera, bandera de
Maldivas (símbolo nacional, proporciones oficiales 2:3) y el cartel de espacio publicitario."""
import math
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from vm_common import REPO

OUT = REPO / "assets" / "generated"


def frond():
    W, H = 256, 1024
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rnd = random.Random(7)
    cx = W // 2
    # raquis
    d.line([(cx, 0), (cx, H)], fill=(96, 110, 52, 255), width=6)
    for y in range(20, H - 10, 9):
        t = y / H
        L = (W * 0.48) * math.sin(math.pi * min(1.0, t * 1.1)) * (0.85 + 0.15 * rnd.random())
        for side in (-1, 1):
            g = 0.75 + 0.25 * rnd.random()
            col = (int(52 * g), int(112 * g), int(36 * g), 255)
            x1 = cx + side * L
            y1 = y + L * 0.55
            d.polygon([(cx, y - 2), (x1, y1 - 3), (x1, y1 + 1), (cx, y + 4)], fill=col)
    img = img.filter(ImageFilter.SMOOTH)
    img.save(OUT / "palm_frond.png")


def flag():
    W, H = 900, 600
    img = Image.new("RGB", (W, H), (210, 16, 52))
    d = ImageDraw.Draw(img)
    d.rectangle([W // 6, H // 4, W - W // 6, H - H // 4], fill=(0, 126, 58))
    cx, cy, r = W * 0.53, H / 2, H * 0.19
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255))
    o = r * 0.36
    d.ellipse([cx - r + o, cy - r * 0.92, cx + r + o, cy + r * 0.92], fill=(0, 126, 58))
    img.save(OUT / "flag_mv.png")


def ad_placeholder():
    W, H = 1024, 256
    img = Image.new("RGB", (W, H), (30, 34, 40))
    d = ImageDraw.Draw(img)
    for x in range(-H, W, 48):
        d.polygon([(x, 0), (x + 24, 0), (x + 24 + H, H), (x + H, H)], fill=(44, 50, 58))
    d.rectangle([6, 6, W - 7, H - 7], outline=(255, 196, 0), width=8)
    try:
        f = ImageFont.truetype("DejaVuSans-Bold.ttf", 64)
        f2 = ImageFont.truetype("DejaVuSans.ttf", 34)
    except OSError:
        f = f2 = ImageFont.load_default()
    d.text((W / 2, H * 0.40), "ESPACIO PUBLICITARIO", fill=(255, 210, 40), font=f, anchor="mm")
    d.text((W / 2, H * 0.74), "tu marca aquí · Vuelo Mundo", fill=(220, 220, 220), font=f2, anchor="mm")
    img.save(OUT / "ad_placeholder.png")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    frond()
    flag()
    ad_placeholder()
    print("listo")
