"""Tinte de referencia del lecho a partir de Sentinel-2 L2A (color verdadero, 10 m).

SOLO referencia de color: la imagen se reduce a 64x64 y se difumina fuerte, y el lecho usa la
variación relativa de color (más verdoso donde hay pasto marino, más claro en arena). No se
calca geometría. Fuente: Copernicus Sentinel-2 (ESA), COG públicos en AWS (sentinel-cogs),
catálogo STAC earth-search. Escena: S2B_43NCE_20260125_0_L2A (nubes 0.12 %)."""
import json

import numpy as np
import rasterio
from PIL import Image, ImageFilter
from rasterio.enums import Resampling
from rasterio.warp import transform_bounds
from rasterio.windows import from_bounds

from landcover import global_to_lonlat
from vm_common import REPO

SCENE = ("https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/43/N/CE/2026/1/"
         "S2B_43NCE_20260125_0_L2A/TCI.tif")
N = 64


def main():
    zones = [z for z in json.load(open(REPO / "data/zone_index.json"))["zones"] if z["kind"] == "site"]
    with rasterio.open(SCENE) as r:
        for z in zones:
            e, n = z["origin"]
            lon0, lat0 = global_to_lonlat(e, n)
            lon1, lat1 = global_to_lonlat(e + z["size"][0], n - z["size"][1])
            b = transform_bounds("EPSG:4326", r.crs, min(lon0, lon1), min(lat0, lat1), max(lon0, lon1), max(lat0, lat1))
            win = from_bounds(*b, r.transform)
            a = r.read([1, 2, 3], window=win, out_shape=(3, N, N), resampling=Resampling.average, boundless=True)
            img = Image.fromarray(np.moveaxis(a, 0, -1).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))
            img.save(REPO / "data/sites" / z["id"] / "s2_tint.png")
            print(z["id"], "media RGB", np.asarray(img).reshape(-1, 3).mean(0).round(1))


if __name__ == "__main__":
    main()
