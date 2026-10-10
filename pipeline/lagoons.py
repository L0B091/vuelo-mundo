"""Corrección de profundidad de lagunas de atolón (Maldivas).

El ETOPO 15" promedia anillos de arrecife y lagunas y deja las lagunas de los atolones en
-5..-15 m, cuando en realidad tienen 30-80 m (fondo 18-55 m en el centro de los atolones del
norte/centro, 80-100 m en el sur; lagunas arenosas de faros ~15 m). Fuentes:
  - IUCN (1991?) "Marine Protected Area Needs in the South Asian Seas Region, vol. 3: Maldives"
  - FAO, Naseer & Hatcher (2001/2004); Purdy & Bertram 1993 (AAPG Studies in Geology 34).
Zonas geomorfológicas: Allen Coral Atlas (CC BY 4.0), WFS público, ver fetch_aca.py.

Modelo (por celda de la grilla de detalle, ~611 m):
  1. Se rasteriza el ACA a 4x la resolución y se calcula la fracción de cada clase por celda.
  2. Anillo = ACA ∪ arrecifes OSM ∪ tierra. Interior del atolón = huecos del anillo cerrado
     (cierre morfológico ~2.5 km para tapar los pasos entre arrecifes).
  3. Fondo del interior: rampa desde el borde (~12 m) hasta dmax(lat) a ~4 km del anillo;
     lagunas chicas (faros, < 25 km²) a 15 m. Se usa min(ETOPO, modelo) (nunca se rellena).
  4. Las clases mapeadas del ACA fijan su profundidad típica y se mezclan por fracción.
"""
import gzip
import json

import numpy as np
from osgeo import gdal, ogr
from scipy import ndimage

from vm_common import RAW, WORK

# clase ACA -> (código, profundidad típica en m; positivo = bajo el nivel del mar)
CLASSES = {
    "Reef Crest": (1, 0.6),
    "Outer Reef Flat": (2, 0.8),
    "Inner Reef Flat": (3, 1.2),
    "Shallow Lagoon": (4, 3.0),
    "Plateau": (5, 8.0),
    "Back Reef Slope": (6, 10.0),
    "Deep Lagoon": (7, 14.0),
    "Sheltered Reef Slope": (8, 18.0),
    "Reef Slope": (9, 20.0),
    "Patch Reefs": (10, 2.0),
    "Terrestrial Reef Flat": (11, 0.5),
}
SUPER = 4


def dmax_for_lat(lat):
    """Profundidad máxima de laguna por latitud (norte ~55 m, Malé ~50 m, sur ~80 m)."""
    return float(np.interp(lat, [-0.7, 1.0, 3.0, 4.5, 7.2], [80.0, 70.0, 50.0, 50.0, 55.0]))


def aca_geojson():
    out = WORK / "aca_geomorphic.geojson"
    if out.exists():
        return str(out)
    feats = []
    for p in sorted((RAW / "aca").glob("*.json.gz")):
        with gzip.open(p, "rt") as f:
            for ft in json.load(f)["features"]:
                c = CLASSES.get(ft["properties"].get("class_name"))
                if c:
                    feats.append({"type": "Feature", "properties": {"code": c[0]}, "geometry": ft["geometry"]})
    out.write_text(json.dumps({"type": "FeatureCollection", "features": feats}))
    print(f"[lagunas] ACA: {len(feats)} polígonos")
    return str(out)


def class_fractions(ds_like):
    gt = ds_like.GetGeoTransform()
    cols, rows = ds_like.RasterXSize, ds_like.RasterYSize
    m = gdal.GetDriverByName("MEM").Create("", cols * SUPER, rows * SUPER, 1, gdal.GDT_Byte)
    m.SetGeoTransform((gt[0], gt[1] / SUPER, 0, gt[3], 0, gt[5] / SUPER))
    m.SetProjection(ds_like.GetProjection())
    src = WORK / "aca_geomorphic_3857.gpkg"
    if not src.exists():
        gdal.VectorTranslate(str(src), aca_geojson(), format="GPKG", dstSRS="EPSG:3857",
                             srcSRS="EPSG:4326", reproject=True, layerName="aca")
    v = gdal.OpenEx(str(src), gdal.OF_VECTOR)
    gdal.Rasterize(m, v, layers=["aca"], attribute="code")
    a = m.GetRasterBand(1).ReadAsArray()
    n = max(c for c, _ in CLASSES.values()) + 1
    fr = np.zeros((n, rows, cols), np.float32)
    blk = a.reshape(rows, SUPER, cols, SUPER)
    for code in range(1, n):
        fr[code] = (blk == code).mean(axis=(1, 3))
    return fr


def disk(r):
    y, x = np.ogrid[-r:r + 1, -r:r + 1]
    return x * x + y * y <= r * r


SHALLOW_CODES = (1, 2, 3, 4, 10, 11)
MODEL_CODES = (5, 7)  # laguna profunda y plataforma: su profundidad sale del modelo


def correct(h, land, reef, ds_like, lat_of_row, step):
    """Devuelve (h corregido int16, máscara de interior de laguna uint8, fracción ACA)."""
    fr = class_fractions(ds_like)
    mapped = fr[1:].sum(axis=0)
    shallow_fr = sum(fr[c] for c in SHALLOW_CODES)
    # (los arrecifes OSM se rasterizan con all_touched y se inflan: solo cuentan para el anillo)
    shallow = (shallow_fr > 0.15) | (land == 1)
    ring = shallow | (mapped > 0.05) | (reef == 1)
    r_close = max(1, int(round(2500.0 / step)))
    closed = ndimage.binary_closing(ring, structure=disk(r_close), border_value=0)
    atoll = ndimage.binary_fill_holes(closed)
    interior = atoll & ~shallow & (h > -300)
    lab, nlab = ndimage.label(interior)
    areas = ndimage.sum(np.ones_like(lab), lab, index=np.arange(1, nlab + 1)) * (step * step) / 1e6
    small = np.isin(lab, np.nonzero(areas < 25.0)[0] + 1)
    dist = ndimage.distance_transform_edt(~shallow) * step
    dmax = np.array([dmax_for_lat(la) for la in lat_of_row], np.float32)[:, None]
    dmax = np.where(small, 15.0, dmax)
    ramp = np.clip((dist - step * 0.5) / 2500.0, 0.0, 1.0)
    ramp = ramp * ramp * (3 - 2 * ramp)
    model = -(8.0 + (dmax - 8.0) * ramp)
    base = h.astype(np.float32)
    base = np.where(interior, np.minimum(base, model), base)
    out = base * (1.0 - np.clip(mapped, 0, 1))
    for name, (code, depth) in CLASSES.items():
        if code in MODEL_CODES:
            out += fr[code] * np.where(interior, model, -depth)
        else:
            out += fr[code] * -depth
    sea = land == 0
    res = np.where(sea & (mapped > 0.0), out, base)
    res = np.where(sea, np.minimum(res, -0.5), res)
    print(f"[lagunas] interior {interior.sum()} celdas ({nlab} lagunas, {int(small.sum())} celdas de faros), "
          f"celdas con ACA {(mapped > 0.05).sum()}")
    return np.round(res).astype(np.int16), interior.astype(np.uint8), mapped
