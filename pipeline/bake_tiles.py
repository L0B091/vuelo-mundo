#!/usr/bin/env python3
"""Hornea las teselas del planeta tosco y del detalle regional de Maldivas.

Salida: data/tiles/L{nivel}/{i}_{j}.vmt  (formato VMT1, ver vm_common.py)
        data/tiles/manifest.json
        docs/previews/*.png (vistas de control)

Todo el remuestreo se hace con GDAL directamente a la cuadrícula global EPSG:3857,
así los bordes compartidos entre teselas vecinas son exactamente las mismas muestras
(no hay escalones al cruzar).
"""
import argparse
import json
import math
import zipfile

import numpy as np
from osgeo import gdal, ogr, osr
from shapely.geometry import LineString, Polygon, mapping, shape
from shapely.ops import linemerge, polygonize, unary_union

from vm_common import (COARSE_LEVEL, COARSE_SAMPLES, DETAIL_LEVEL, DETAIL_SAMPLES,
                       HALF, RAW, REPO, TILES_OUT, WORK, WORLD, global_to_lonlat,
                       lonlat_to_global, tile_of, tile_origin, tile_size, write_tile)

gdal.UseExceptions()
gdal.PushErrorHandler("CPLQuietErrorHandler")  # silencia avisos DBF de Natural Earth
gdal.SetCacheMax(512 * 1024 * 1024)

# Región con detalle (lon_min, lat_min, lon_max, lat_max): atolones de Maldivas.
MV_REGION = (72.5, -0.8, 74.0, 7.2)


def srs3857():
    s = osr.SpatialReference()
    s.ImportFromEPSG(3857)
    return s.ExportToWkt()


def warp_grid(src, e0, n0, cols, rows, step, resample):
    """Remuestrea `src` a una grilla de puntos: centro del píxel (0,0) = (e0, n0)."""
    bounds = [e0 - step / 2, n0 - (rows - 1) * step - step / 2,
              e0 + (cols - 1) * step + step / 2, n0 + step / 2]
    ds = gdal.Warp("", src, format="MEM", dstSRS="EPSG:3857", srcSRS="EPSG:4326",
                   outputBounds=bounds, width=cols, height=rows, resampleAlg=resample,
                   outputType=gdal.GDT_Float32, dstNodata=-32768, multithread=True,
                   warpMemoryLimit=1024)
    a = ds.GetRasterBand(1).ReadAsArray().astype(np.float32)
    return a, ds


def fill_nodata(a, nodata=-32768):
    bad = a <= nodata + 1
    if not bad.any():
        return a
    # Relleno simple: replica la fila/columna válida más cercana (solo bordes extremos).
    from scipy import ndimage
    idx = ndimage.distance_transform_edt(bad, return_distances=False, return_indices=True)
    return a[tuple(idx)]


def vector_to_3857(srcs, name):
    """Une capas vectoriales (en 4326) y las reproyecta a 3857 recortando a ±85.05°."""
    WORK.mkdir(parents=True, exist_ok=True)
    out = WORK / f"{name}_3857.gpkg"
    if out.exists():
        out.unlink()
    first = True
    for s in srcs:
        gdal.VectorTranslate(str(out), s, format="GPKG", dstSRS="EPSG:3857",
                             srcSRS="EPSG:4326", reproject=True,
                             clipSrc=[-180, -85.05, 180, 85.05], layerName=name,
                             accessMode=None if first else "append",
                             geometryType="PROMOTE_TO_MULTI" if "islets" not in name else None,
                             explodeCollections=False)
        first = False
    return str(out)


def rasterize(vec_path, ds_like, all_touched):
    drv = gdal.GetDriverByName("MEM")
    m = drv.Create("", ds_like.RasterXSize, ds_like.RasterYSize, 1, gdal.GDT_Byte)
    m.SetGeoTransform(ds_like.GetGeoTransform())
    m.SetProjection(srs3857())
    v = gdal.OpenEx(vec_path, gdal.OF_VECTOR)
    for li in range(v.GetLayerCount()):
        gdal.Rasterize(m, v, layers=[v.GetLayer(li).GetName()], burnValues=[1],
                       allTouched=all_touched)
    return m.GetRasterBand(1).ReadAsArray().astype(np.uint8)


def ne_path(name):
    z = RAW / f"{name}.zip"
    return f"/vsizip/{z}/{name}.shp"


# ---------------------------------------------------------------- OSM (Maldivas)
def osm_polygons():
    js = json.loads((RAW / "osm_maldives.json").read_text())
    coast_lines, islands, reefs = [], [], []
    for el in js["elements"]:
        tags = el.get("tags", {})
        if el["type"] == "way" and "geometry" in el:
            pts = [(p["lon"], p["lat"]) for p in el["geometry"]]
            if len(pts) < 2:
                continue
            closed = pts[0] == pts[-1] and len(pts) >= 4
            if tags.get("natural") == "coastline":
                (islands.append(Polygon(pts)) if closed else coast_lines.append(LineString(pts)))
            elif tags.get("natural") == "reef":
                reefs.append(Polygon(pts).buffer(0) if closed else LineString(pts).buffer(0.0002))
        elif el["type"] == "relation" and tags.get("natural") == "reef":
            outers = [LineString([(p["lon"], p["lat"]) for p in m["geometry"]])
                      for m in el.get("members", []) if m.get("role") == "outer" and "geometry" in m]
            reefs.extend(polygonize(linemerge(outers)) if outers else [])
    if coast_lines:
        merged = linemerge(coast_lines)
        islands.extend(polygonize(merged))
    islands = [p.buffer(0) for p in islands if p.is_valid or p.buffer(0).is_valid]
    return islands, [r for r in reefs if not r.is_empty]


def write_geojson(polys, path):
    fc = {"type": "FeatureCollection",
          "features": [{"type": "Feature", "properties": {}, "geometry": mapping(p)} for p in polys]}
    path.write_text(json.dumps(fc))
    return str(path)


# ---------------------------------------------------------------- horneado
def bake_coarse(stats):
    n_t = 1 << COARSE_LEVEL
    step = tile_size(COARSE_LEVEL) / (COARSE_SAMPLES - 1)
    N = n_t * (COARSE_SAMPLES - 1) + 1
    src = f'NETCDF:"{RAW / "etopo60_surface.nc"}":z'
    print(f"[tosco] remuestreando ETOPO 60\" a {N}x{N} (paso {step:.0f} m)…")
    a, ds = warp_grid(src, -HALF, HALF, N, N, step, "average")
    a = fill_nodata(a)
    # continuidad en el antimeridiano: columna 0 y N-1 son la misma longitud
    edge = 0.5 * (a[:, 0] + a[:, -1])
    a[:, 0] = edge
    a[:, -1] = edge
    print("[tosco] máscara de tierra Natural Earth…")
    vec = vector_to_3857([ne_path("ne_10m_land"), ne_path("ne_10m_minor_islands")], "ne_land")
    land = rasterize(vec, ds, all_touched=False)
    land[:, -1] = land[:, 0]
    h = apply_mask_rules(a, land, reef=None)
    write_level(COARSE_LEVEL, COARSE_SAMPLES, h, land, 0, 0, n_t, n_t, stats)
    preview(h, land, REPO / "docs" / "previews" / "planeta_L6.png", 2048)


def apply_mask_rules(a, land, reef):
    h = np.round(a).astype(np.int32)
    # Tierra según la costa vectorial pero el DEM la hunde (islas chicas): levantar a +1/+2 m
    lift = (land == 1) & (h <= 0) & (h > -60)
    h[lift] = 2 if reef is not None else 1
    # Mar según la costa vectorial pero el DEM marca tierra baja: bajar a -1 m
    sink = (land == 0) & (h > 0) & (h < 40)
    h[sink] = -1
    if reef is not None:
        r = (reef == 1) & (land == 0)
        h[r & (h < -2)] = -2
        h[r & (h > -1)] = -1
    return np.clip(h, -11000, 9000).astype(np.int16)


def carve_sites(h, e0, n0, step):
    """Baja el terreno a nivel 0 bajo los micro-mapas del índice: el micro-mapa se apoya
    ENCIMA del conector y su suelo caminable nunca queda tapado por el relieve tosco."""
    idx = REPO / "data" / "zone_index.json"
    if not idx.exists():
        return 0
    count = 0
    for z in json.loads(idx.read_text())["zones"]:
        if z.get("kind") != "site":
            continue
        (oe, on), (se, sn) = z["origin"], z["size"]
        c0 = int(math.floor((oe - e0) / step)) - 1
        c1 = int(math.ceil((oe + se - e0) / step)) + 1
        r0 = int(math.floor((n0 - on) / step)) - 1
        r1 = int(math.ceil((n0 - (on - sn)) / step)) + 1
        if c1 < 0 or r1 < 0 or c0 >= h.shape[1] or r0 >= h.shape[0]:
            continue
        sl = h[max(r0, 0):r1 + 1, max(c0, 0):c1 + 1]
        sl[sl > 1] = 1  # 1 m: por debajo del suelo del micro-mapa (2 m)
        count += 1
    return count


def write_level(level, samples, h, land, i0, j0, ni, nj, stats):
    k = samples - 1
    total = 0
    for jj in range(nj):
        for ii in range(ni):
            th = h[jj * k: jj * k + samples, ii * k: ii * k + samples]
            tm = land[jj * k: jj * k + samples, ii * k: ii * k + samples]
            i, j = i0 + ii, j0 + jj
            total += write_tile(TILES_OUT / f"L{level}" / f"{i}_{j}.vmt", level, i, j, th, tm)
    stats[f"L{level}"] = {"tiles": ni * nj, "bytes": total, "samples": samples,
                          "i0": i0, "j0": j0, "ni": ni, "nj": nj}
    print(f"[L{level}] {ni * nj} teselas, {total / 1e6:.1f} MB")


def bake_detail(stats):
    ratio = 1 << (DETAIL_LEVEL - COARSE_LEVEL)
    lon0, lat0, lon1, lat1 = MV_REGION
    e0, n1 = lonlat_to_global(lon0, lat1)
    e1, n0 = lonlat_to_global(lon1, lat0)
    ci0, cj0 = tile_of(COARSE_LEVEL, e0, n1)
    ci1, cj1 = tile_of(COARSE_LEVEL, e1, n0)
    # El detalle cubre teselas toscas COMPLETAS: así el cambio tosco->detalle no deja huecos.
    i0, j0 = ci0 * ratio, cj0 * ratio
    ni, nj = (ci1 - ci0 + 1) * ratio, (cj1 - cj0 + 1) * ratio
    step = tile_size(DETAIL_LEVEL) / (DETAIL_SAMPLES - 1)
    cols, rows = ni * (DETAIL_SAMPLES - 1) + 1, nj * (DETAIL_SAMPLES - 1) + 1
    oe, on = tile_origin(DETAIL_LEVEL, i0, j0)
    vrt = str(WORK / "etopo15.vrt")
    WORK.mkdir(parents=True, exist_ok=True)
    gdal.BuildVRT(vrt, [str(p) for p in sorted(RAW.glob("etopo15_*.tif"))])
    print(f"[detalle] teselas toscas {ci0}..{ci1} x {cj0}..{cj1}; grilla {cols}x{rows} paso {step:.0f} m")
    a, ds = warp_grid(vrt, oe, on, cols, rows, step, "average")
    a = fill_nodata(a)
    islands, reefs = osm_polygons()
    print(f"[detalle] OSM: {len(islands)} islas, {len(reefs)} arrecifes")
    # Islas grandes: rasterizado normal. Islas menores que una celda: solo su centroide
    # (así no desaparecen, pero tampoco se inflan como con all_touched).
    m_per_deg = 111320.0
    cell_deg2 = (step / m_per_deg) ** 2
    big = [p for p in islands if p.area >= cell_deg2]
    small = [p.representative_point() for p in islands if p.area < cell_deg2]
    isl = write_geojson(big, WORK / "osm_islands.geojson")
    isl_small = write_geojson(small, WORK / "osm_islets.geojson")
    rf = write_geojson(reefs, WORK / "osm_reefs.geojson")
    ne = vector_to_3857([ne_path("ne_10m_land"), ne_path("ne_10m_minor_islands")], "ne_land_d")
    land = rasterize(ne, ds, all_touched=False)
    land |= rasterize(vector_to_3857([isl], "osm_islands"), ds, all_touched=False)
    land |= rasterize(vector_to_3857([isl_small], "osm_islets"), ds, all_touched=True)
    reef = rasterize(vector_to_3857([rf], "osm_reefs"), ds, all_touched=True)
    h = apply_mask_rules(a, land, reef)
    print("[detalle] micro-mapas tallados:", carve_sites(h, oe, on, step))
    write_level(DETAIL_LEVEL, DETAIL_SAMPLES, h, land, i0, j0, ni, nj, stats)
    stats["detail_parents"] = [[ci, cj] for cj in range(cj0, cj1 + 1) for ci in range(ci0, ci1 + 1)]
    preview(h, land, REPO / "docs" / "previews" / "maldivas_L8.png", 1600)


def preview(h, land, path, max_px):
    from PIL import Image
    path.parent.mkdir(parents=True, exist_ok=True)
    s = max(1, int(math.ceil(max(h.shape) / max_px)))
    hh = h[::s, ::s].astype(np.float32)
    ll = land[::s, ::s]
    rgb = np.zeros(hh.shape + (3,), np.float32)
    d = np.clip(-hh, 0, None)
    t = np.clip(np.log1p(d) / math.log1p(6000), 0, 1)[..., None]
    shallow = np.array([90, 225, 215], np.float32)
    deep = np.array([8, 30, 80], np.float32)
    sea = shallow * (1 - t) + deep * t
    u = np.clip(hh / 3000, 0, 1)[..., None]
    lowl = np.array([70, 140, 60], np.float32)
    high = np.array([170, 150, 120], np.float32)
    lnd = lowl * (1 - u) + high * u
    rgb[:] = np.where((ll == 1)[..., None] | (hh > 0)[..., None], lnd, sea)
    Image.fromarray(rgb.astype(np.uint8)).save(path)
    print("vista previa:", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-coarse", action="store_true")
    ap.add_argument("--skip-detail", action="store_true")
    args = ap.parse_args()
    man_path = TILES_OUT / "manifest.json"
    stats = json.loads(man_path.read_text()).get("levels", {}) if man_path.exists() else {}
    if not args.skip_coarse:
        bake_coarse(stats)
    if not args.skip_detail:
        bake_detail(stats)
    manifest = {
        "format": "VMT1",
        "projection": "EPSG:3857 (Mercator esférico), metros; origen de tesela = esquina NO",
        "radius_m": 6378137.0,
        "coarse_level": COARSE_LEVEL,
        "detail_level": DETAIL_LEVEL,
        "levels": stats,
        "sources": ["ETOPO 2022 v1 60s/15s surface (NOAA NCEI)",
                    "Natural Earth 10m land + minor islands",
                    "OpenStreetMap natural=coastline / natural=reef (Maldivas)"],
    }
    man_path.parent.mkdir(parents=True, exist_ok=True)
    man_path.write_text(json.dumps(manifest, indent=1))
    print("manifest:", man_path)


if __name__ == "__main__":
    main()
