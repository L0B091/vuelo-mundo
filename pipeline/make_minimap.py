"""Minimapa: mosaico de las baldosas de detalle L8 (tierra / arrecife somero / laguna / mar) en
una sola imagen pequeña con su georreferencia, para el HUD (data/minimap/mv.png + mv.json)."""
import json
from pathlib import Path

import numpy as np
from PIL import Image

from vm_common import HALF, REPO, read_tile, tile_size

PX = 160  # píxeles por baldosa L8 (156 km -> ~1 km/px)


def main():
    files = sorted((REPO / "data/tiles/L8").glob("*.vmt"))
    ij = [tuple(int(v) for v in f.stem.split("_")) for f in files]
    i0, i1 = min(a for a, _ in ij), max(a for a, _ in ij)
    j0, j1 = min(b for _, b in ij), max(b for _, b in ij)
    img = np.zeros(((j1 - j0 + 1) * PX, (i1 - i0 + 1) * PX, 4), np.uint8)
    img[:] = (16, 42, 92, 200)
    for f, (i, j) in zip(files, ij):
        t = read_tile(f)
        h, m = t["heights"], t["mask"]
        idx = np.linspace(0, h.shape[0] - 1, PX).astype(int)
        h = h[np.ix_(idx, idx)].astype(float)
        m = m[np.ix_(idx, idx)]
        c = np.zeros((PX, PX, 4), np.uint8)
        c[:] = (16, 42, 92, 200)
        c[h > -40] = (24, 92, 150, 210)
        c[h > -12] = (40, 170, 190, 220)
        c[h > -2] = (120, 220, 210, 230)
        c[m > 0] = (236, 222, 170, 255)
        y, x = (j - j0) * PX, (i - i0) * PX
        img[y:y + PX, x:x + PX] = c
    out = REPO / "data/minimap"
    out.mkdir(exist_ok=True)
    Image.fromarray(img, "RGBA").save(out / "mv.png")
    s = tile_size(8)
    json.dump({"e0": i0 * s - HALF, "n0": HALF - j0 * s, "m_per_px": s / PX,
               "w": img.shape[1], "h": img.shape[0]}, open(out / "mv.json", "w"))
    print(img.shape)


if __name__ == "__main__":
    main()
