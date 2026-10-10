"""ESA WorldCover 2021 v200 (10 m, CC BY 4.0) y Copernicus GLO-30 DSM (ESA, licencia
Copernicus DEM) para los micro-mapas: clase de cobertura y altura de superficie en un punto.

Solo se usan como datos de ubicación (dónde hay árboles, qué altura tiene el dosel); no se
calca geometría. Descarga: buckets públicos de AWS Open Data (ver fetch())."""
import math
import urllib.request

import numpy as np

from vm_common import RAW

WC_URL = "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_{t}_Map.tif"
DEM_URL = ("https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_{t}_DEM/"
           "Copernicus_DSM_COG_10_{t}_DEM.tif")
R = 6378137.0
TREE, SHRUB, GRASS, BUILT, BARE, WATER, WETLAND, MANGROVE = 10, 20, 30, 50, 60, 80, 90, 95


def _get(url, name):
    out = RAW / "landcover" / name
    out.parent.mkdir(parents=True, exist_ok=True)
    if not out.exists():
        urllib.request.urlretrieve(url, out)
    return out


class Raster:
    def __init__(self, path):
        import rasterio
        self.r = rasterio.open(path)
        self.a = self.r.read(1)

    def at(self, lon, lat):
        row, col = self.r.index(lon, lat)
        if 0 <= row < self.a.shape[0] and 0 <= col < self.a.shape[1]:
            return self.a[row, col]
        return None


def worldcover(lat, lon):
    t = "N%02dE%03d" % (math.floor(lat / 3) * 3, math.floor(lon / 3) * 3)
    return Raster(_get(WC_URL.format(t=t), f"wc_{t}.tif"))


def dsm(lat, lon):
    t = "N%02d_00_E%03d_00" % (math.floor(lat), math.floor(lon))
    return Raster(_get(DEM_URL.format(t=t), f"dsm_{t}.tif"))


def global_to_lonlat(e, n):
    return math.degrees(e / R), math.degrees(math.atan(math.sinh(n / R)))
