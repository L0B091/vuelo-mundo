#!/usr/bin/env python3
"""Descarga zonas geomorfológicas del Allen Coral Atlas (CC BY 4.0) para Maldivas.

Fuente: WFS público https://allencoralatlas.org/geoserver/ows, capa
coral-atlas:geomorphic_data_verbose (NO la copia de Google Earth Engine).
Se pide por celdas de 0.5 grados y se pagina; cada celda queda en raw/aca/<lat>_<lon>.json.gz.
"""
import gzip
import json
import os
import sys
import time
import urllib.parse
import urllib.request

from vm_common import RAW

WFS = "https://allencoralatlas.org/geoserver/ows"
LAYER = "coral-atlas:geomorphic_data_verbose"
LAT0, LAT1, LON0, LON1, STEP = -1.0, 7.5, 72.5, 74.0, 0.5


def get(params):
    url = WFS + "?" + urllib.parse.urlencode(params)
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "vuelo-mundo-pipeline/0.2 (curl-compatible)"})
            with urllib.request.urlopen(req, timeout=300) as r:
                return json.loads(r.read())
        except Exception as e:  # noqa: BLE001
            print("  reintento", attempt, e, file=sys.stderr)
            time.sleep(5 * (attempt + 1))
    raise RuntimeError("WFS falló: " + url)


def main():
    out_dir = os.path.join(RAW, "aca")
    os.makedirs(out_dir, exist_ok=True)
    lat = LAT0
    total = 0
    while lat < LAT1 - 1e-9:
        lon = LON0
        while lon < LON1 - 1e-9:
            path = os.path.join(out_dir, "%.1f_%.1f.json.gz" % (lat, lon))
            if not os.path.exists(path):
                # sin paginar: la capa no tiene clave primaria (GeoServer no puede ordenar)
                d = get({
                    "service": "WFS", "version": "2.0.0", "request": "GetFeature",
                    "typeNames": LAYER, "outputFormat": "application/json",
                    "bbox": "%f,%f,%f,%f,urn:ogc:def:crs:EPSG::4326" % (lat, lon, lat + STEP, lon + STEP),
                })
                feats = d.get("features", [])
                nm = d.get("numberMatched")
                if isinstance(nm, int) and nm != len(feats):
                    raise RuntimeError("respuesta truncada: %s de %s" % (len(feats), nm))
                with gzip.open(path + ".tmp", "wt") as f:
                    json.dump({"type": "FeatureCollection", "features": feats}, f)
                os.replace(path + ".tmp", path)
                print("celda %.1f %.1f: %d polígonos" % (lat, lon, len(feats)), flush=True)
            total += 1
            lon += STEP
        lat += STEP
    print("listo,", total, "celdas")


if __name__ == "__main__":
    main()
