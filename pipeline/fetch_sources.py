#!/usr/bin/env python3
"""Descarga las fuentes abiertas (nada de Google). Ver ATTRIBUTION.md.

- ETOPO 2022 60" (NOAA NCEI): relieve + batimetría global (incluye GEBCO).
- ETOPO 2022 15" (NOAA NCEI): teselas 15°x15° para la región de Maldivas.
- Natural Earth 10m: tierra, islas menores, costa (dominio público).
- OpenStreetMap (Overpass API): costa e arrecifes de Maldivas (ODbL).
"""
import json
import sys
import time
import urllib.parse
import urllib.request

from vm_common import RAW

ETOPO60 = ("etopo60_surface.nc",
           "https://www.ngdc.noaa.gov/thredds/fileServer/global/ETOPO2022/60s/"
           "60s_surface_elev_netcdf/ETOPO_2022_v1_60s_N90W180_surface.nc")
ETOPO15_TILES = ["N15E060", "N00E060", "N15E075", "N00E075"]
ETOPO15_URL = ("https://www.ngdc.noaa.gov/mgg/global/relief/ETOPO2022/data/15s/"
               "15s_surface_elev_gtif/ETOPO_2022_v1_15s_{t}_surface.tif")
NE = ["ne_10m_land", "ne_10m_minor_islands", "ne_10m_coastline"]
NE_URL = "https://naciscdn.org/naturalearth/10m/physical/{n}.zip"

# Caja de Maldivas para OSM (sur, oeste, norte, este)
MV_BBOX = (-1.0, 72.4, 7.6, 74.0)
OVERPASS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]


def get(url, dst):
    if dst.exists() and dst.stat().st_size > 0:
        print("ya existe", dst.name)
        return
    print("descargando", url)
    tmp = dst.with_suffix(dst.suffix + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": "vuelo-mundo-pipeline/0.1"})
    with urllib.request.urlopen(req, timeout=600) as r, open(tmp, "wb") as f:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            f.write(b)
    tmp.rename(dst)


def overpass(dst):
    if dst.exists() and dst.stat().st_size > 0:
        print("ya existe", dst.name)
        return
    s, w, n, e = MV_BBOX
    q = f"""[out:json][timeout:300];
(
  way["natural"="coastline"]({s},{w},{n},{e});
  way["natural"="reef"]({s},{w},{n},{e});
  relation["natural"="reef"]({s},{w},{n},{e});
);
out geom;"""
    print("consultando Overpass (OSM) para Maldivas…")
    data = urllib.parse.urlencode({"data": q}).encode()
    js = None
    for attempt in range(3):
        for url in OVERPASS:
            try:
                req = urllib.request.Request(url, data=data,
                                             headers={"User-Agent": "vuelo-mundo-pipeline/0.1"})
                with urllib.request.urlopen(req, timeout=600) as r:
                    js = json.load(r)
                break
            except Exception as ex:  # servidores públicos a veces saturados
                print("  fallo", url, ex)
                time.sleep(5)
        if js is not None:
            break
    if js is None:
        raise SystemExit("Overpass no respondió; reintentar más tarde")
    dst.write_text(json.dumps(js))
    print("elementos OSM:", len(js.get("elements", [])))


def main():
    RAW.mkdir(parents=True, exist_ok=True)
    get(ETOPO60[1], RAW / ETOPO60[0])
    for t in ETOPO15_TILES:
        get(ETOPO15_URL.format(t=t), RAW / f"etopo15_{t}.tif")
    for n in NE:
        get(NE_URL.format(n=n), RAW / f"{n}.zip")
    overpass(RAW / "osm_maldives.json")
    print("listo:", RAW)


if __name__ == "__main__":
    sys.exit(main())
