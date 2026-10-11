"""Atlas de letreros de comercios de Malé (Dhivehi + inglés), 2 columnas x 8 filas de 512x128.

Fuentes: Noto Sans Thaana Bold (SIL OFL 1.1) para Thaana y DejaVu Sans Bold para el latín.
Los nombres son genéricos (rubros), sin marcas reales. El texto Dhivehi no fue revisado por
un hablante nativo.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import random

REPO = Path(__file__).resolve().parents[1]
THAANA = REPO / "assets/fonts/NotoSansThaana.ttf"
LATIN = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SIGNS = [
    ("ފިހާރަ", "STORE"), ("ހޮޓާ", "CAFE & HOTAA"), ("ބޭސް ފިހާރަ", "PHARMACY"),
    ("ފޮތް ފިހާރަ", "BOOKSHOP"), ("މަސް", "FRESH FISH"), ("ބޭކަރީ", "BAKERY"),
    ("", "MOBILE & ELECTRONICS"), ("", "TAILOR"), ("", "HARDWARE"), ("", "GROCERY"),
    ("", "SALON"), ("ހޮޓާ", "TEA SHOP"), ("", "TRAVEL & FERRY"), ("ފިހާރަ", "MINI MART"),
    ("", "DIVE SHOP"), ("", "SOUVENIRS"),
]
PALETTE = [((200, 30, 40), (255, 255, 255)), ((20, 90, 160), (255, 255, 255)), ((250, 210, 40), (30, 30, 30)),
           ((30, 130, 70), (255, 255, 255)), ((240, 240, 235), (180, 20, 30)), ((20, 20, 25), (255, 200, 40)),
           ((0, 150, 160), (255, 255, 255)), ((120, 40, 120), (255, 255, 255))]


def main():
    W, H = 512, 128
    atlas = Image.new("RGB", (W * 2, H * 8))
    ft = ImageFont.truetype(str(THAANA), 46)
    rnd = random.Random(7)
    for i, (dv, en) in enumerate(SIGNS):
        bg, fg = PALETTE[rnd.randrange(len(PALETTE))]
        im = Image.new("RGB", (W, H), bg)
        d = ImageDraw.Draw(im)
        d.rectangle([4, 4, W - 5, H - 5], outline=fg, width=4)
        fl = ImageFont.truetype(LATIN, 44 if len(en) < 14 else 32)
        if dv:
            d.text((W - 24, H / 2), dv, font=ft, fill=fg, anchor="rm", direction="rtl")
            d.text((24, H / 2), en, font=fl, fill=fg, anchor="lm")
        else:
            d.text((W / 2, H / 2), en, font=fl, fill=fg, anchor="mm")
        atlas.paste(im, ((i % 2) * W, (i // 2) * H))
    out = REPO / "assets/textures/shop_signs.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(out)
    print("atlas:", out)


if __name__ == "__main__":
    main()
