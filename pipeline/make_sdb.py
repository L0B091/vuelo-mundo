"""Batimetría derivada de satélite (SDB) con Sentinel-2 L2A: razón de logaritmos azul/verde
(Stumpf et al. 2003, "Determination of water depth with high-resolution satellite imagery
over variable bottom types", Limnol. Oceanogr. 48:547-556).

  r = ln(n·B02) / ln(n·B03)     d = m1·r - m0

Es una medición radiométrica del satélite (como un DEM), no un calco. Calibración laxa: m1, m0
se ajustan para que las medianas por clase geomorfológica del Allen Coral Atlas caigan en los
rangos publicados (planicie de arrecife ~1.5 m, laguna somera ~6 m, laguna profunda ~20 m,
límite práctico del método en agua clara). Se recorta a 0.3-20 m y solo se usa donde el modelo
existente dice < 25 m; es una ESTIMACIÓN (sin sondeos de campo).
"""
import json
import math

import numpy as np
import rasterio
from PIL import Image
from rasterio.enums import Resampling
from rasterio.warp import transform_bounds
from rasterio.windows import from_bounds

from landcover import global_to_lonlat
from vm_common import REPO

BASE = ("https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/43/N/CE/2026/1/"
        "S2B_43NCE_20260125_0_L2A/")
OFFSET = 1000.0  # BOA_ADD_OFFSET de la línea base 04.00+
N_STUMPF = 1000.0
TARGET = {2: 1.5, 3: 1.5, 6: 6.0, 7: 20.0}  # clase geomorfológica -> profundidad típica (m)
MAX_D = 20.0


def read(band, lon0, lat0, lon1, lat1, w, h):
    with rasterio.open(BASE + band + ".tif") as r:
        b = transform_bounds("EPSG:4326", r.crs, min(lon0, lon1), min(lat0, lat1), max(lon0, lon1), max(lat0, lat1))
        a = r.read(1, window=from_bounds(*b, r.transform), out_shape=(h, w), resampling=Resampling.average,
                   boundless=True).astype(np.float32)
    return np.clip((a - OFFSET) / 10000.0, 1e-4, 1.0)


def ratio_grid(lon0, lat0, lon1, lat1, w, h):
    b2, b3, b8 = (read(b, lon0, lat0, lon1, lat1, w, h) for b in ("B02", "B03", "B08"))
    b3 = np.maximum(b3, 0.002)
    r = np.log(N_STUMPF * np.maximum(b2, 0.002)) / np.log(N_STUMPF * b3)
    water = (b8 < 0.04) & (b3 > 0.005)  # tierra/espuma/nube brillan en el infrarrojo cercano
    return r, water


def fit(zones):
    """Ajuste por mínimos cuadrados de (m1, m0) a las medianas por clase en todas las zonas."""
    xs, ys = [], []
    for z in zones:
        n = 192
        lon0, lat0 = global_to_lonlat(*z["origin"])
        lon1, lat1 = global_to_lonlat(z["origin"][0] + z["size"][0], z["origin"][1] - z["size"][1])
        r, water = ratio_grid(lon0, lat0, lon1, lat1, n, n)
        geo = np.asarray(Image.open(REPO / "data/sites" / z["id"] / "geomorph.png").resize((n, n), Image.NEAREST))
        if geo.ndim == 3:
            geo = geo[..., 0]
        for c, d in TARGET.items():
            sel = water & (geo == c)
            if sel.sum() > 30:
                xs.append(float(np.median(r[sel])))
                ys.append(d)
                print(z["id"], "clase", c, "n", int(sel.sum()), "r mediana", round(xs[-1], 4))
    A = np.vstack([xs, np.ones(len(xs))]).T
    m1, b = np.linalg.lstsq(A, np.array(ys), rcond=None)[0]
    print("ajuste: d = %.1f * r %+.1f" % (m1, b))
    return m1, b


def sdb(lon0, lat0, lon1, lat1, w, h, m1, b):
    r, water = ratio_grid(lon0, lat0, lon1, lat1, w, h)
    d = np.clip(m1 * r + b, 0.3, MAX_D)
    d[~water] = np.nan
    return d


_FIT = None


def _fit():
    global _FIT
    if _FIT is None:
        f = json.load(open(REPO / "data/sdb_fit.json"))
        _FIT = (f["m1"], f["b"])
    return _FIT


def grid_global(e0, n0, w_m, h_m, w, h):
    """SDB (m, NaN donde no hay agua o queda fuera de la escena) en una grilla w x h que cubre
    el rectángulo global (e0, n0) - (e0 + w_m, n0 - h_m), fila 0 = norte."""
    m1, b = _fit()
    lon0, lat0 = global_to_lonlat(e0, n0)
    lon1, lat1 = global_to_lonlat(e0 + w_m, n0 - h_m)
    return sdb(lon0, lat0, lon1, lat1, w, h, m1, b)


def blend(model, est, max_model=25.0, w=0.7):
    """Mezcla el modelo (m, >0 agua) con la estimación SDB donde ambos son agua somera."""
    out = model.copy()
    ok = np.isfinite(est) & (model > 0.0) & (model < max_model)
    w = np.broadcast_to(np.asarray(w, np.float32), model.shape)
    out[ok] = (1 - w[ok]) * model[ok] + w[ok] * est[ok]
    return out


def zone_weight(n, w_m, h_m, band=250.0, w=0.7):
    """Peso SDB en una grilla de zona: se apaga en la franja del borde, donde la zona empalma
    con las teselas L8 (que solo llevan el SDB promediado a 611 m)."""
    x = np.linspace(0, w_m, n)[None, :]
    z = np.linspace(0, h_m, n)[:, None]
    e = np.minimum(np.minimum(x, w_m - x), np.minimum(z, h_m - z))
    return w * np.clip(e / band, 0.0, 1.0)


def main():
    zones = [z for z in json.load(open(REPO / "data/zone_index.json"))["zones"] if z["kind"] == "site"]
    m1, b = fit(zones)
    json.dump({"m1": m1, "b": b, "scene": BASE}, open(REPO / "data/sdb_fit.json", "w"), indent=1)


if __name__ == "__main__":
    main()
