#!/usr/bin/env python3
"""Mapa bentónico por micro-mapa (Allen Coral Atlas, CC BY 4.0): clase del fondo marino.

Rasteriza las clases bentónicas (capa coral-atlas:benthic_data_verbose, bajada por
fetch_aca.py benthic) en una textura de 512x512 que cubre el rectángulo de cada zona
(origen NO, x este, y sur). R = clase: 0 sin dato, 1 arena, 2 pasto marino, 3 coral/alga,
4 escombro, 5 roca, 6 microalgas. El sombreador del lecho elige material por clase.
También geomorph.png (capa geomórfica): 1 cresta (rompiente), 2/3 planicie arrecifal
exterior/interior, 4 talud, 5 talud interior, 6 laguna somera, 7 laguna profunda, 8 meseta.
"""
import glob
import gzip
import json
from pathlib import Path

from PIL import Image, ImageDraw

from vm_common import RAW, global_to_lonlat, lonlat_to_global

REPO = Path(__file__).resolve().parent.parent
N = 512
CLASSES = {"Sand": 1, "Seagrass": 2, "Coral/Algae": 3, "Rubble": 4, "Rock": 5, "Microalgal Mats": 6}


GEO = {"Reef Crest": 1, "Outer Reef Flat": 2, "Inner Reef Flat": 3, "Terrestrial Reef Flat": 3,
       "Reef Slope": 4, "Sheltered Reef Slope": 4, "Back Reef Slope": 5, "Shallow Lagoon": 6,
       "Deep Lagoon": 7, "Plateau": 8}
# orden de pintado: lo grande primero, la cresta (rompiente) encima de todo
GEO_ORDER = [7, 8, 4, 5, 6, 3, 2, 1]


def load(sub="aca_benthic"):
    feats = []
    for f in sorted(glob.glob(str(RAW) + "/" + sub + "/*.json.gz")):
        feats += json.load(gzip.open(f))["features"]
    return feats


def rings(geom):
    if geom["type"] == "Polygon":
        yield geom["coordinates"]
    elif geom["type"] == "MultiPolygon":
        yield from geom["coordinates"]


def raster(feats, z, table, order, fill_hole):
    e0, n0 = z["origin"]
    w, h = z["size"]
    img = Image.new("L", (N, N), 0)
    dr = ImageDraw.Draw(img)
    fs = [f for f in feats if table.get(f["properties"].get("class_name")) and f.get("geometry")]
    fs.sort(key=lambda f: order.index(table[f["properties"]["class_name"]]))
    for f in fs:
        c = table[f["properties"]["class_name"]]
        for poly in rings(f["geometry"]):
            pts = [((e - e0) / w * N, (n0 - n) / h * N) for e, n in (lonlat_to_global(a, b) for a, b in poly[0])]
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            if max(xs) < 0 or min(xs) > N or max(ys) < 0 or min(ys) > N:
                continue
            dr.polygon(pts, fill=c)
            for hole in poly[1:]:
                dr.polygon([((e - e0) / w * N, (n0 - n) / h * N) for e, n in
                            (lonlat_to_global(a, b) for a, b in hole)], fill=fill_hole)
    return img


def main_geo(zones):
    feats = []
    for f in sorted(glob.glob(str(RAW) + "/aca/4.0_73.5*.json.gz")):
        feats += json.load(gzip.open(f))["features"]
    for z in zones:
        img = raster(feats, z, GEO, GEO_ORDER, 0)
        img.save(REPO / "data/sites" / z["id"] / "geomorph.png")
        print(z["id"], "geomorfología", img.histogram()[:9])


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
    main_geo(zones)


if __name__ == "__main__":
    main()


def main_tiles(n_px=2048):
    """Geomorfología para el agua de las teselas L8 (~76 m/px): el color de planicies, lagunas
    someras y crestas sigue fuera de los micro-mapas y su borde deja de notarse."""
    global N
    from vm_common import tile_origin, tile_size
    feats = []
    for f in sorted(glob.glob(str(RAW) + "/aca/*.json.gz")):
        feats += json.load(gzip.open(f))["features"]
    print("polígonos ACA", len(feats))
    out = REPO / "data/tiles/L8/geo"
    out.mkdir(exist_ok=True)
    sz = tile_size(8)
    N = n_px
    for p in sorted((REPO / "data/tiles/L8").glob("*.vmt")):
        i, j = map(int, p.stem.split("_"))
        e0, n0 = tile_origin(8, i, j)
        lon0, lat0 = global_to_lonlat(e0, n0)
        lon1, lat1 = global_to_lonlat(e0 + sz, n0 - sz)
        sub = []
        for f in feats:
            g = f.get("geometry")
            if not g:
                continue
            c = g["coordinates"][0][0] if g["type"] == "MultiPolygon" else g["coordinates"][0]
            lo, la = c[0][0], c[0][1]
            if lon0 - 0.05 < lo < lon1 + 0.05 and lat1 - 0.05 < la < lat0 + 0.05:
                sub.append(f)
        if not sub:
            continue
        img = raster(sub, {"origin": (e0, n0), "size": (sz, sz)}, GEO, GEO_ORDER, 0)
        img.save(out / f"{i}_{j}.png")
        print(p.stem, "polígonos", len(sub))
