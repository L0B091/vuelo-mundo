#!/usr/bin/env python3
"""Mapa bentónico por micro-mapa (Allen Coral Atlas, CC BY 4.0): clase del fondo marino.

Rasteriza las clases bentónicas (capa coral-atlas:benthic_data_verbose, bajada por
fetch_aca.py benthic) en una textura de 512x512 que cubre el rectángulo de cada zona
(origen NO, x este, y sur). R = clase: 0 sin dato, 1 arena, 2 pasto marino, 3 coral/alga,
4 escombro, 5 roca, 6 microalgas. El sombreador del lecho elige material por clase.
"""
import glob
import gzip
import json
from pathlib import Path

from PIL import Image, ImageDraw

from vm_common import RAW, lonlat_to_global

REPO = Path(__file__).resolve().parent.parent
N = 512
CLASSES = {"Sand": 1, "Seagrass": 2, "Coral/Algae": 3, "Rubble": 4, "Rock": 5, "Microalgal Mats": 6}


def load():
    feats = []
    for f in sorted(glob.glob(str(RAW) + "/aca_benthic/*.json.gz")):
        feats += json.load(gzip.open(f))["features"]
    return feats


def rings(geom):
    if geom["type"] == "Polygon":
        yield geom["coordinates"]
    elif geom["type"] == "MultiPolygon":
        yield from geom["coordinates"]


def main():
    feats = load()
    zones = [z for z in json.load(open(REPO / "data/zone_index.json"))["zones"] if z["kind"] == "site"]
    for z in zones:
        e0, n0 = z["origin"]
        w, h = z["size"]
        img = Image.new("L", (N, N), 0)
        dr = ImageDraw.Draw(img)
        cnt = 0
        # primero clases "de fondo" (arena) y encima las más chicas
        order = sorted(feats, key=lambda f: [1, 4, 6, 5, 3, 2].index(CLASSES.get(f["properties"].get("class_name"), 1)))
        for f in order:
            c = CLASSES.get(f["properties"].get("class_name"))
            if not c or not f.get("geometry"):
                continue
            for poly in rings(f["geometry"]):
                pts = []
                for lon, lat in poly[0]:
                    e, n = lonlat_to_global(lon, lat)
                    pts.append(((e - e0) / w * N, (n0 - n) / h * N))
                xs = [p[0] for p in pts]
                ys = [p[1] for p in pts]
                if max(xs) < 0 or min(xs) > N or max(ys) < 0 or min(ys) > N:
                    continue
                dr.polygon(pts, fill=c)
                for hole in poly[1:]:
                    hp = []
                    for lon, lat in hole:
                        e, n = lonlat_to_global(lon, lat)
                        hp.append(((e - e0) / w * N, (n0 - n) / h * N))
                    dr.polygon(hp, fill=1)
                cnt += 1
        out = REPO / "data/sites" / z["id"] / "benthic.png"
        img.save(out)
        hist = img.histogram()[:7]
        print(z["id"], "polígonos", cnt, "píxeles por clase", hist)


if __name__ == "__main__":
    main()
