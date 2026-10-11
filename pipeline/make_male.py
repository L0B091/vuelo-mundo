#!/usr/bin/env python3
"""Micro-mapa REAL de Malé a partir de OpenStreetMap (ODbL), sin datos de Google.

Entrada:  raw/osm_male.json (Overpass, ver fetch_male en este archivo)
Salida:   data/sites/<zona>/meta.json + capas binarias (float32 / int32) que
          tools/gen_male.gd convierte en escenas Godot (res://scenes/zones/<zona>.scn).

La isla se parte en dos zonas (oeste/este) con borde común exacto. Todo se genera en metros
reales locales a la zona: x = este, z = sur, y = arriba; origen = esquina NO de la zona.
Lo que OSM no tiene (muchas manzanas sin edificios cargados) se completa con lotes
procedurales dentro de las manzanas reales: se marcan como "procedural" en meta.json.
"""
import hashlib
import json
import math
import struct
import sys
import urllib.parse
import urllib.request

import mapbox_earcut as earcut
import numpy as np
from shapely import affinity
from shapely.geometry import LineString, MultiPolygon, Point, Polygon, box
from shapely.ops import linemerge, polygonize, unary_union
from shapely.prepared import prep

from vm_common import DETAIL_SAMPLES, RAW, REPO, TILES_OUT, lonlat_to_global, read_tile, tile_of, tile_origin, tile_size

BBOX = (73.4950, 4.1600, 73.5350, 4.1900)  # lon0, lat0, lon1, lat1 (descarga)
# zonas: lon0, lat_top, lon1, lat_bottom
ZONE_W = ("mv_male_oeste", "Malé (oeste)", 73.4975, 4.1880, 73.5150, 4.1655)
ZONE_E = ("mv_male_este", "Malé (este)", 73.5150, 4.1880, 73.5320, 4.1655)
DECK_Y = 1.8          # suelo de la isla (m sobre el mar)
SEAWALL_BOTTOM = -2.5
FLOOR_H = 3.2
ROAD_W = {"primary": 11.0, "primary_link": 7.0, "secondary": 9.0, "tertiary": 7.5,
          "tertiary_link": 6.0, "unclassified": 6.0, "residential": 5.5, "living_street": 5.0,
          "service": 4.0, "pedestrian": 5.0, "footway": 2.5, "path": 2.0}
SIDEWALK_W = 1.6
SHOP_ROADS = {"primary", "secondary", "tertiary"}
# modelos listos (Kenney, CC0): los nombres los resuelve tools/gen_male.gd (KENNEY)
VEHICLES = ("car", "taxi", "van", "hatchback", "car", "covered_car", "taxi", "hatchback", "delivery")
# motos de Malé: casi todas scooters; algunas motos y bicicletas
TWO_WHEEL = ("scooter_a", "scooter_b", "scooter_c", "scooter_d", "scooter_a", "scooter_c", "motorbike",
             "bicycle", "bicycle_delivery")
SHOP_FRONT = ("fruit_stand", "bread_stand", "freezer", "crate", "barrel", "shop_shelf", "gas", "planter")
EXTRA_KINDS = ("taxi", "van", "delivery", "suv", "pickup", "traffic_light", "sign_stop", "sign_street",
               "elec_pole", "cone", "planter", "fruit_stand", "bread_stand", "freezer", "crate", "barrel",
               "shop_shelf", "cafe_table", "stool", "roof_tank", "antenna", "stall_roof", "fish_crate", "hydrant", "wood_crate", "utility_box", "manhole", "trashbag",
               "gas", "bananas", "tyre", "covered_car", "barrier", "hatchback", "laundry", "aframe", "container",
               "crane", "shutter", "frangipani", "banana_clump") + TWO_WHEEL[:4] + TWO_WHEEL[6:]


def market_point(z):
    """Mercado de pescado de Malé (frente al puerto norte), en coordenadas locales de la zona."""
    from vm_common import lonlat_to_global
    e, n = lonlat_to_global(73.5087, 4.1781)[:2]
    return ((e - z.e0) / z.k, (z.n0 - n) / z.k)
LANDMARKS = {
    151402193: "islamic_centre",       # Masjid-al-Sultan Muhammad Thakurufaanu Al Auzam
    1317932599: "hukuru_miskiy",       # Mezquita del Viernes antigua (piedra de coral)
    270847401: "republic_square",      # Jumhooree Maidan
    602727296: "artificial_beach",
}
R = 6378137.0


def fetch_male():
    q = ("[out:json][timeout:180];(way({1},{0},{3},{2});relation({1},{0},{3},{2}););out body geom;"
         .format(*BBOX))
    for m in ("https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"):
        try:
            req = urllib.request.Request(m, data=urllib.parse.urlencode({"data": q}).encode(),
                                         headers={"User-Agent": "vuelo-mundo-pipeline/0.2"})
            with urllib.request.urlopen(req, timeout=240) as r:
                (RAW / "osm_male.json").write_bytes(r.read())
                return
        except Exception as e:  # noqa: BLE001
            print("Overpass falló", m, e)
    raise SystemExit("sin datos OSM")


def k_at(n):
    return math.cosh(n / R)


class Zone:
    def __init__(self, spec, k):
        self.id, self.name, lon0, lat0, lon1, lat1 = spec
        self.e0, self.n0 = lonlat_to_global(lon0, lat0)
        e1, n1 = lonlat_to_global(lon1, lat1)
        self.k = k
        self.w = (e1 - self.e0) / k
        self.h = (self.n0 - n1) / k
        self.rect = box(0, 0, self.w, self.h)

    def to_local(self, lon, lat):
        e, n = lonlat_to_global(lon, lat)
        return ((e - self.e0) / self.k, (self.n0 - n) / self.k)


# ------------------------------------------------------------------ geometría de malla
class Mesh:
    def __init__(self):
        self.v, self.n, self.uv, self.c, self.uv2, self.i = [], [], [], [], [], []

    def add_poly(self, poly, y, uv_scale=1.0, color=(1, 1, 1, 1), normal=(0, 1, 0), y_fn=None):
        if poly.is_empty:
            return
        polys = poly.geoms if hasattr(poly, "geoms") else [poly]
        for p in polys:
            if p.geom_type != "Polygon" or p.area < 0.05:
                continue
            p = p.simplify(0.05)
            rings = [np.asarray(p.exterior.coords)[:-1]] + [np.asarray(r.coords)[:-1] for r in p.interiors]
            rings = [r for r in rings if len(r) >= 3]
            if not rings:
                continue
            verts = np.concatenate(rings)
            ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
            tri = earcut.triangulate_float64(verts.astype(np.float64), ends)
            base = len(self.v)
            for x, z in verts:
                yy = y_fn(x, z) if y_fn else y
                self.v.append((x, yy, z))
                self.n.append(normal)
                self.uv.append((x * uv_scale, z * uv_scale))
                self.uv2.append((0.0, 0.0))
                self.c.append(color)
            # Godot: cara frontal = horaria vista desde el lado de la normal
            for a in range(0, len(tri), 3):
                t3 = [base + int(tri[a]), base + int(tri[a + 1]), base + int(tri[a + 2])]
                p0, p1, p2 = (np.asarray(self.v[q]) for q in t3)
                if np.cross(p1 - p0, p2 - p0)[1] > 0:
                    t3 = [t3[0], t3[2], t3[1]]
                self.i += t3

    def add_quad(self, p0, p1, y0, y1, color=(1, 1, 1, 1), u0=0.0, uv2=(0.0, 0.0)):
        """Pared vertical de p0 a p1 (x,z), normal hacia la derecha del recorrido."""
        (x0, z0), (x1, z1) = p0, p1
        dx, dz = x1 - x0, z1 - z0
        L = math.hypot(dx, dz)
        if L < 0.05:
            return
        nx, nz = dz / L, -dx / L
        base = len(self.v)
        for (x, z, yy, u) in ((x0, z0, y0, u0), (x1, z1, y0, u0 + L), (x1, z1, y1, u0 + L), (x0, z0, y1, u0)):
            self.v.append((x, yy, z))
            self.n.append((nx, 0.0, nz))
            self.uv.append((u, yy))
            self.uv2.append(uv2)
            self.c.append(color)
        self.i += [base, base + 1, base + 2, base, base + 2, base + 3]

    def add_tri_list(self, verts, normals, color=(1, 1, 1, 1)):
        base = len(self.v)
        for p, nn in zip(verts, normals):
            self.v.append(p)
            self.n.append(nn)
            self.uv.append((p[0], p[2]))
            self.uv2.append((0.0, 0.0))
            self.c.append(color)
        self.i += list(range(base, base + len(verts)))

    def write(self, path):
        v = np.asarray(self.v, np.float32).reshape(-1, 3)
        with open(path, "wb") as f:
            f.write(struct.pack("<4sII", b"VMM1", len(v), len(self.i)))
            f.write(v.tobytes())
            f.write(np.asarray(self.n, np.float32).reshape(-1, 3).tobytes())
            f.write(np.asarray(self.uv, np.float32).reshape(-1, 2).tobytes())
            f.write(np.asarray(self.uv2, np.float32).reshape(-1, 2).tobytes())
            f.write(np.asarray(self.c, np.float32).reshape(-1, 4).tobytes())
            f.write(np.asarray(self.i, np.int32).tobytes())
        return len(v), len(self.i) // 3


def walls_of(poly, y0, y1, mesh, color, uv2=(0.0, 0.0), shop_edges=None):
    polys = poly.geoms if hasattr(poly, "geoms") else [poly]
    for p in polys:
        if p.geom_type != "Polygon":
            continue
        p = Polygon(p.exterior.coords) if not p.exterior.is_ccw else p
        ext = list(p.exterior.coords)
        if p.exterior.is_ccw:  # en (x, z-sur) CCW => recorrido horario visto desde arriba
            ext = ext[::-1]
        u = 0.0
        for a in range(len(ext) - 1):
            shop = shop_edges(ext[a], ext[a + 1]) if shop_edges else 0.0
            mesh.add_quad(ext[a], ext[a + 1], y0, y1, color, u, (uv2[0], shop))
            u += math.dist(ext[a], ext[a + 1])
        for r in p.interiors:
            ring = list(r.coords)
            if not r.is_ccw:
                ring = ring[::-1]
            for a in range(len(ring) - 1):
                mesh.add_quad(ring[a], ring[a + 1], y0, y1, color)


def hh(s):
    return int(hashlib.md5(str(s).encode()).hexdigest()[:8], 16)


def tint(seed):
    # paleta de Malé: blancos, cremas, pasteles cálidos, algún celeste/verde agua
    # paleta de Malé: mucho blanco y crema, pero también pasteles fuertes (turquesa, verde,
    # amarillo, rosa, celeste, terracota) como en las fachadas reales
    pal = [(0.95, 0.94, 0.90), (0.93, 0.87, 0.74), (0.97, 0.80, 0.55), (0.62, 0.84, 0.86),
           (0.62, 0.82, 0.62), (0.94, 0.68, 0.62), (0.90, 0.90, 0.90), (0.98, 0.88, 0.45),
           (0.60, 0.72, 0.92), (0.90, 0.68, 0.82), (0.85, 0.55, 0.42), (0.55, 0.78, 0.74),
           (0.96, 0.94, 0.90), (0.75, 0.88, 0.95)]
    c = pal[hh(seed) % len(pal)]
    return (c[0], c[1], c[2], 1.0)


# ------------------------------------------------------------------ OSM
def load_osm():
    return load_osm_file("osm_male.json")


def load_osm_file(name):
    js = json.loads((RAW / name).read_text())
    out = {"coast": [], "islands": [], "buildings": [], "roads": [], "parks": [], "piers": [],
           "breakwaters": [], "beaches": [], "squares": [], "pitches": [], "marinas": []}
    for el in js["elements"]:
        tags = el.get("tags", {})
        geo = None
        if el["type"] == "way" and "geometry" in el:
            pts = [(p["lon"], p["lat"]) for p in el["geometry"]]
            closed = len(pts) >= 4 and pts[0] == pts[-1]
            geo = (pts, closed)
        elif el["type"] == "relation" and tags.get("type") == "multipolygon":
            outers = [LineString([(p["lon"], p["lat"]) for p in m["geometry"]])
                      for m in el.get("members", []) if m.get("role") == "outer" and "geometry" in m]
            polys = list(polygonize(linemerge(outers))) if outers else []
            if polys:
                geo = (unary_union(polys), "poly")
        if geo is None:
            continue
        pts, closed = geo
        item = {"id": el["id"], "tags": tags}
        if closed == "poly":
            item["poly_ll"] = pts
        elif closed:
            item["poly_ll"] = Polygon(pts).buffer(0)
        else:
            item["line_ll"] = LineString(pts)
        if tags.get("natural") == "coastline":
            (out["islands"] if "poly_ll" in item else out["coast"]).append(item)
        elif "building" in tags and "poly_ll" in item:
            out["buildings"].append(item)
        elif tags.get("highway") in ROAD_W and "line_ll" in item:
            out["roads"].append(item)
        elif tags.get("man_made") == "pier":
            out["piers"].append(item)
        elif tags.get("man_made") == "breakwater":
            out["breakwaters"].append(item)
        elif tags.get("natural") == "beach" or el["id"] == 602727296:
            out["beaches"].append(item)
        elif tags.get("place") == "square" or tags.get("highway") == "pedestrian" and "poly_ll" in item:
            out["squares"].append(item)
        elif tags.get("leisure") in ("park", "garden", "common") or tags.get("landuse") == "grass":
            out["parks"].append(item)
        elif tags.get("leisure") == "pitch":
            out["pitches"].append(item)
        elif tags.get("leisure") == "marina":
            out["marinas"].append(item)
    return out


def to_local_geom(g, z):
    def f(x, y, zz=None):
        e = np.radians(x) * R
        n = R * np.log(np.tan(np.pi / 4 + np.radians(y) / 2))
        return ((e - z.e0) / z.k, (z.n0 - n) / z.k)
    from shapely.ops import transform
    return transform(f, g)


def island_polygon(osm):
    polys = [it["poly_ll"] for it in osm["islands"]]
    lines = [it["line_ll"] for it in osm["coast"]]
    if lines:
        polys += list(polygonize(linemerge(lines)))
    # la costa OSM se dibuja con el mar a la derecha: polígonos de tierra
    land = unary_union([p for p in polys if p.area > 1e-8])
    return land


# ------------------------------------------------------------------ batimetría (L8)
class L8:
    def __init__(self):
        self.cache = {}

    def depth(self, e, n):
        i, j = tile_of(8, e, n)
        key = (i, j)
        if key not in self.cache:
            t = read_tile(TILES_OUT / f"L8/{i}_{j}.vmt")
            h = t[0] if isinstance(t, tuple) else t["heights"]
            self.cache[key] = np.asarray(h, np.float32).reshape(DETAIL_SAMPLES, DETAIL_SAMPLES)
        a = self.cache[key]
        oe, on = tile_origin(8, i, j)
        s = tile_size(8) / (DETAIL_SAMPLES - 1)
        fx, fy = (e - oe) / s, (on - n) / s
        x0, y0 = min(int(fx), DETAIL_SAMPLES - 2), min(int(fy), DETAIL_SAMPLES - 2)
        tx, ty = fx - x0, fy - y0
        v = (a[y0, x0] * (1 - tx) * (1 - ty) + a[y0, x0 + 1] * tx * (1 - ty)
             + a[y0 + 1, x0] * (1 - tx) * ty + a[y0 + 1, x0 + 1] * tx * ty)
        return -float(v)


# ------------------------------------------------------------------ generación por zona
def lots_in_block(block, seed):
    """Parte una manzana en lotes (~11 x 14 m) alineados al rectángulo mínimo de la manzana."""
    mrr = block.minimum_rotated_rectangle
    c = list(mrr.exterior.coords)
    ang = math.degrees(math.atan2(c[1][1] - c[0][1], c[1][0] - c[0][0]))
    rb = affinity.rotate(block, -ang, origin=block.centroid)
    x0, z0, x1, z1 = rb.bounds
    lw, ld = 10.0 + (seed % 5), 13.0 + (seed // 5 % 4)
    out = []
    x = x0
    while x < x1:
        z = z0
        while z < z1:
            cell = box(x, z, x + lw, z + ld).intersection(rb)
            if not cell.is_empty and cell.area > 45.0:
                cell = cell.buffer(-0.4, join_style=2)
                if not cell.is_empty and cell.area > 35.0:
                    out.append(affinity.rotate(cell, ang, origin=block.centroid))
            z += ld
        x += lw
    return out


def build_zone(z, osm, l8, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    rect = z.rect
    land_all = to_local_geom(island_polygon(osm), z)
    land = land_all.intersection(rect)
    loc = lambda it: to_local_geom(it.get("poly_ll") or it["line_ll"], z)  # noqa: E731

    # calles
    road_polys, road_info = [], []
    for it in osm["roads"]:
        hw = it["tags"]["highway"]
        g = loc(it)
        if not g.intersects(rect.buffer(30)):
            continue
        w = ROAD_W[hw]
        road_polys.append(g.buffer(w / 2, cap_style=2, join_style=2))
        road_info.append((hw, g, w, it["tags"].get("name:en") or it["tags"].get("name", "")))
    roads = unary_union(road_polys).intersection(land) if road_polys else Polygon()
    vehic = unary_union([g.buffer(w / 2, cap_style=2, join_style=2) for hw, g, w, _ in road_info
                         if hw not in ("footway", "path", "pedestrian")]) if road_info else Polygon()
    sidewalks = vehic.buffer(SIDEWALK_W, join_style=2).difference(vehic).intersection(land)
    shop_lines = unary_union([g for hw, g, w, _ in road_info if hw in SHOP_ROADS]) if road_info else None

    def lpolys(key):
        return [(it, loc(it)) for it in osm[key] if loc(it).intersects(rect)]

    parks = unary_union([g for _, g in lpolys("parks") if g.geom_type in ("Polygon", "MultiPolygon")]).intersection(land)
    squares = unary_union([g for _, g in lpolys("squares") if g.geom_type in ("Polygon", "MultiPolygon")]).intersection(land)
    pitches = unary_union([g for _, g in lpolys("pitches") if g.geom_type in ("Polygon", "MultiPolygon")]).intersection(land)
    beaches = unary_union([g for _, g in lpolys("beaches") if g.geom_type in ("Polygon", "MultiPolygon")])
    beaches = beaches.intersection(rect) if not beaches.is_empty else beaches
    deck = land.difference(beaches) if not beaches.is_empty else land

    meshes = {k: Mesh() for k in ("deck", "seawall", "road", "sidewalk", "paint", "park", "square",
                                  "pitch", "beach", "pier", "breakwater", "walls", "roofs", "seabed")}
    meshes["deck"].add_poly(deck, DECK_Y, 1 / 4)
    meshes["road"].add_poly(roads.difference(squares), DECK_Y + 0.02, 1 / 6)
    meshes["sidewalk"].add_poly(sidewalks.difference(squares), DECK_Y + 0.035, 1 / 2)
    meshes["park"].add_poly(parks.difference(roads), DECK_Y + 0.03, 1 / 4)
    meshes["square"].add_poly(squares, DECK_Y + 0.04, 1 / 3)
    meshes["pitch"].add_poly(pitches.difference(roads), DECK_Y + 0.03, 1 / 4, (0.25, 0.55, 0.3, 1))

    # muro de costa: caras verticales del borde de la isla (no en el borde de la zona)
    coast = land_all.boundary.intersection(rect)
    for seg in (coast.geoms if hasattr(coast, "geoms") else [coast]):
        if seg.geom_type != "LineString":
            continue
        cs = list(seg.coords)
        land_side = land_all.exterior.is_ccw if land_all.geom_type == "Polygon" else True
        for a in range(len(cs) - 1):
            p0, p1 = cs[a], cs[a + 1]
            meshes["seawall"].add_quad(p1, p0, SEAWALL_BOTTOM, DECK_Y)  # se arregla la cara en Godot (doble)

    # playa: arena en rampa desde el muelle hasta el agua
    if not beaches.is_empty:
        inland = deck.boundary

        def beach_y(x, zz):
            d = Point(x, zz).distance(inland)
            return DECK_Y - min(1.0, d / 35.0) * (DECK_Y + 1.6)
        dense = beaches.segmentize(4.0)
        meshes["beach"].add_poly(dense, 0.0, 1 / 3, y_fn=beach_y)

    # muelles y escolleras
    pier_polys = []
    for it, g in lpolys("piers"):
        poly = g if g.geom_type in ("Polygon", "MultiPolygon") else g.buffer(2.5, cap_style=2)
        poly = poly.intersection(rect).difference(land)
        pier_polys.append(poly)
        meshes["pier"].add_poly(poly, DECK_Y - 0.3, 1 / 3)
        walls_of(poly, -1.0, DECK_Y - 0.3, meshes["pier"], (0.8, 0.8, 0.78, 1))
    for it, g in lpolys("breakwaters"):
        poly = g if g.geom_type in ("Polygon", "MultiPolygon") else g.buffer(3.0, cap_style=1)
        poly = poly.intersection(rect).difference(land)
        meshes["breakwater"].add_poly(poly, 1.2, 1 / 2)
        walls_of(poly, -1.5, 1.2, meshes["breakwater"], (1, 1, 1, 1))

    # edificios OSM (cada edificio va a la zona de su centroide: no se cortan paredes)
    blds, landmarks = [], []
    road_block = roads.buffer(0.3)
    for it in osm["buildings"]:
        g = loc(it)
        if g.is_empty or not rect.contains(g.centroid):
            continue
        g = g.buffer(0)
        if it["id"] in LANDMARKS:
            landmarks.append({"kind": LANDMARKS[it["id"]], "osm_id": it["id"],
                              "name": it["tags"].get("name:en") or it["tags"].get("name", ""),
                              "poly": [list(c) for c in g.exterior.coords] if g.geom_type == "Polygon" else []})
        t = it["tags"]
        lv = t.get("building:levels")
        if "height" in t:
            try:
                height = float(str(t["height"]).split()[0])
            except ValueError:
                height = None
        else:
            height = None
        if height is None and lv:
            try:
                height = float(lv) * FLOOR_H + 1.0
            except ValueError:
                height = None
        if height is None:
            height = (3 + hh(it["id"]) % 6) * FLOOR_H + 1.0
        if LANDMARKS.get(it["id"]) == "hukuru_miskiy":
            height = 5.5
        elif LANDMARKS.get(it["id"]) == "islamic_centre":
            height = 14.0
        blds.append({"poly": g, "h": height, "seed": it["id"], "procedural": False,
                     "kind": LANDMARKS.get(it["id"], "building")})
    for it in osm["squares"] + osm["beaches"]:
        if it["id"] in LANDMARKS and "poly_ll" in it:
            g = loc(it)
            if rect.contains(g.centroid):
                landmarks.append({"kind": LANDMARKS[it["id"]], "osm_id": it["id"],
                                  "name": it["tags"].get("name:en") or it["tags"].get("name", ""),
                                  "poly": [list(c) for c in g.exterior.coords] if g.geom_type == "Polygon" else []})

    # relleno procedural de manzanas sin edificios en OSM
    osm_b = unary_union([b["poly"].buffer(1.0) for b in blds]) if blds else Polygon()
    free = deck.difference(roads.buffer(SIDEWALK_W + 0.5)).difference(parks).difference(squares)
    free = free.difference(pitches).difference(osm_b).buffer(-1.0).buffer(0.5)
    n_proc = 0
    for blk in (free.geoms if hasattr(free, "geoms") else [free]):
        if blk.geom_type != "Polygon" or blk.area < 80:
            continue
        for lot in lots_in_block(blk, hh(round(blk.centroid.x)) % 40):
            if lot.geom_type != "Polygon" or not rect.contains(lot.centroid):
                continue
            s = hh((round(lot.centroid.x, 1), round(lot.centroid.y, 1)))
            floors = 3 + s % 7
            blds.append({"poly": lot, "h": floors * FLOOR_H + 1.0, "seed": s, "procedural": True,
                         "kind": "building"})
            n_proc += 1

    def shop_edges_for(height):
        def f(p0, p1):
            if shop_lines is None or shop_lines.is_empty:
                return 0.0
            mid = Point((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
            return 1.0 if mid.distance(shop_lines) < 12.0 and math.dist(p0, p1) > 4.0 else 0.0
        return f

    # huellas de edificios (para el test de props pegados a fachadas)
    fp = [[[round(x, 2), round(y, 2)] for x, y in b["poly"].exterior.coords] + [[round(b["h"], 2)]]
          for b in blds if b["poly"].geom_type == "Polygon" and rect.contains(b["poly"].centroid)]
    fp_dir = REPO / "data/sites" / z.id
    fp_dir.mkdir(parents=True, exist_ok=True)
    with open(fp_dir / "footprints.json", "w") as f:
        json.dump(fp, f, separators=(",", ":"))
    ad_slots = []
    for b in blds:
        g, h = b["poly"], b["h"]
        y1 = DECK_Y + h
        col = (0.78, 0.66, 0.5, 1) if b["kind"] == "hukuru_miskiy" else tint(b["seed"])
        style = 1.0 if b["kind"] == "hukuru_miskiy" else 0.0
        if b["kind"] in ("building",):
            walls_of(g, DECK_Y - 0.2, y1, meshes["walls"], col, (style, 0.0), shop_edges_for(h))
        else:
            walls_of(g, DECK_Y - 0.2, y1, meshes["walls"], col, (style, 0.0))
        meshes["roofs"].add_poly(g, y1, 1 / 4)
        # cartel publicitario: una cara mirando a una calle comercial, bajo la primera losa
        if b["kind"] == "building" and shop_lines is not None and not shop_lines.is_empty:
            ext = list(g.exterior.coords) if g.geom_type == "Polygon" else []
            if ext and not g.exterior.is_ccw:
                pass
            best = None
            for a in range(len(ext) - 1):
                p0, p1 = ext[a], ext[a + 1]
                L = math.dist(p0, p1)
                mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
                d = Point(mid).distance(shop_lines)
                if L >= 6.0 and d < 12.0 and (best is None or d < best[0]):
                    best = (d, p0, p1, L)
            if best is not None and len(ad_slots) < 400:
                d, p0, p1, L = best
                # normal hacia afuera del edificio
                mx, mz = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
                nx, nz = (p1[1] - p0[1]) / L, -(p1[0] - p0[0]) / L
                if g.contains(Point(mx + nx * 0.5, mz + nz * 0.5)):
                    nx, nz = -nx, -nz
                ad_slots.append({"id": f"{z.id}_ad_{len(ad_slots):03d}", "pos": [mx + nx * 0.08, DECK_Y + 3.6, mz + nz * 0.08],
                                 "normal": [nx, 0.0, nz], "size": [min(L - 1.0, 6.0), 1.2]})

    # pasos de cebra: en cruces de calles vehiculares (franjas blancas)
    nodes = {}
    for hw, g, w, _ in road_info:
        if hw in ("footway", "path", "pedestrian", "service"):
            continue
        for c in (g.coords[0], g.coords[-1]):
            nodes.setdefault((round(c[0], 1), round(c[1], 1)), []).append((g, w))
    n_cross = 0
    for (x, zz), lst in nodes.items():
        if len(lst) < 3 or not rect.contains(Point(x, zz)) or not land.contains(Point(x, zz)):
            continue
        for g, w in lst:
            # franja a 3 m del cruce, a lo largo de cada brazo
            d0 = 0.0 if Point(g.coords[0]).distance(Point(x, zz)) < 0.5 else g.length
            off = w / 2 + 1.5
            pt = g.interpolate(off if d0 == 0.0 else g.length - off)
            pn = g.interpolate(off + 0.5 if d0 == 0.0 else g.length - off - 0.5)
            dx, dz = pn.x - pt.x, pn.y - pt.y
            L = math.hypot(dx, dz)
            if L < 1e-3:
                continue
            dx, dz = dx / L, dz / L
            px, pz = -dz, dx
            for s in range(-int(w / 1.2), int(w / 1.2) + 1):
                cx, cz = pt.x + px * s * 0.6, pt.y + pz * s * 0.6
                stripe = Polygon([(cx - px * 0.2 - dx * 1.4, cz - pz * 0.2 - dz * 1.4),
                                  (cx + px * 0.2 - dx * 1.4, cz + pz * 0.2 - dz * 1.4),
                                  (cx + px * 0.2 + dx * 1.4, cz + pz * 0.2 + dz * 1.4),
                                  (cx - px * 0.2 + dx * 1.4, cz - pz * 0.2 + dz * 1.4)])
                stripe = stripe.intersection(vehic)
                meshes["paint"].add_poly(stripe, DECK_Y + 0.03)
            n_cross += 1

    # agua y lecho marino de la zona (reemplazan a L8 dentro del rectángulo)
    N = 192
    depth = np.zeros((N, N), np.float32)
    sea = rect.difference(land_all)
    edge = rect.exterior
    coast_line = land_all.boundary
    for r in range(N):
        for c in range(N):
            x, zz = c / (N - 1) * z.w, r / (N - 1) * z.h
            p = Point(x, zz)
            if land_all.contains(p) and not beaches.contains(p):
                depth[r, c] = -1.0
                continue
            dl8 = max(l8.depth(z.e0 + x * z.k, z.n0 - zz * z.k), 1.0)
            dc = p.distance(coast_line)
            model = min(dl8, 1.0 + dc * 0.06)
            if beaches.contains(p):
                model = -0.2
            we = max(0.0, 1.0 - p.distance(edge) / 250.0)
            depth[r, c] = model * (1 - we) + dl8 * we
    import make_sdb
    est = make_sdb.grid_global(z.e0, z.n0, z.w * z.k, z.h * z.k, N, N)
    depth = make_sdb.blend(depth, est, w=make_sdb.zone_weight(N, z.w, z.h)).astype(np.float32)
    depth.astype(np.float32).tofile(out_dir / "depth.f32")
    # lecho: grilla 48x48 con la misma profundidad (escalada por k como L8: y = -d)
    G = 64
    for r in range(G - 1):
        for c in range(G - 1):
            quad = []
            for (rr, cc) in ((r, c), (r, c + 1), (r + 1, c + 1), (r + 1, c)):
                x, zz = cc / (G - 1) * z.w, rr / (G - 1) * z.h
                d = depth[min(N - 1, round(rr / (G - 1) * (N - 1))), min(N - 1, round(cc / (G - 1) * (N - 1)))]
                quad.append((x, -max(d, 0.5) if d > -0.5 else -0.5, zz))
            v = [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]
            meshes["seabed"].add_tri_list(v, [(0, 1, 0)] * 6)

    stats = {}
    for name, m in meshes.items():
        if m.i:
            stats[name] = m.write(out_dir / f"{name}.vmm")
    # recorrido de prueba: por Majeedhee Magu (la avenida principal este-oeste)
    meta = {
        "id": z.id, "name": z.name, "size": [z.w, z.h], "deck_y": DECK_Y, "k": z.k,
        "origin_global": [z.e0, z.n0], "depth_n": N, "landmarks": landmarks, "ad_slots": ad_slots,
        "stats": {"buildings_osm": sum(1 for b in blds if not b["procedural"]),
                  "buildings_procedural": n_proc, "crossings": n_cross, "ad_slots": len(ad_slots),
                  "meshes": stats},
        "palms": palm_points(parks, squares, sidewalks, road_info, z),
        "props": life_props(street_props(z, road_info, blds, parks, squares, land, rect, shop_lines),
                            z, parks, squares, beaches, pier_polys, land, rect, road_info),
        "paths": npc_paths(road_info, land, rect, blds),
        "boats": boat_points(land_all, rect),
        "streets": [{"name": nm, "kind": hw, "pts": [list(c) for c in g.coords]}
                    for hw, g, w, nm in road_info if nm and hw in SHOP_ROADS],
    }
    (out_dir / "meta.json").write_text(json.dumps(meta, ensure_ascii=False))
    print(z.id, json.dumps(meta["stats"]))
    return meta


def _frac(*a):
    return (hh(tuple(round(v, 1) for v in a)) % 10000) / 10000.0


def _along(g, step, off=0.0):
    """Puntos cada `step` m a lo largo de una línea: (x, z, dx, dz) con la dirección local."""
    L = g.length
    t = off
    while t < L:
        p = g.interpolate(t)
        q = g.interpolate(min(L, t + 0.5))
        dx, dz = q.x - p.x, q.y - p.y
        n = math.hypot(dx, dz) or 1.0
        yield p.x, p.y, dx / n, dz / n
        t += step


def _pts_in(poly, n, seed):
    """n puntos deterministas dentro de un polígono (rechazo sobre su caja)."""
    out, k = [], 0
    if poly is None or poly.is_empty:
        return out
    x0, y0, x1, y1 = poly.bounds
    while len(out) < n and k < n * 30:
        k += 1
        px = x0 + _frac(k, seed, 51) * (x1 - x0)
        py = y0 + _frac(seed, k, 52) * (y1 - y0)
        if poly.contains(Point(px, py)):
            out.append((px, py))
    return out


def life_props(out, z, parks, squares, beaches, piers, land, rect, road_info):
    """Vida en la calle: gente estática (multitud lejana barata, MultiMesh), puestos de comida con
    filas, gente en cafés y puestos, plazas, playa artificial, muelles; vegetación variada;
    puerto (bolardos, gaviotas, boyas, pesquero). Las cantidades se ralean por perfil en el juego."""
    Q = {k: [] for k in ("person_stand", "person_sit", "person_talk", "person_kid", "ice_kiosk", "ice_cart",
                         "ticket_kiosk", "food_counter", "queue_post", "palm_lean", "palm_young", "sea_grape",
                         "pandanus", "bollard", "seagull", "buoy", "trawler")}
    Y = DECK_Y + 0.02

    def crowd(px, pz, yaw, kind=None, sc=None):
        f = _frac(px, pz, 61)
        kind = kind or ("person_talk" if f < 0.35 else "person_stand")
        Q[kind].append([px, Y, pz, yaw, sc or (0.9 + _frac(pz, px, 62) * 0.2)])

    # cafés: dos sentados por mesa (en los taburetes)
    for it in out.get("stool", []):
        if _frac(it[0], it[2], 63) < 0.75:
            Q["person_sit"].append([it[0], Y, it[2], it[3] + math.pi, 1.0])
    # puestos de fruta/pan/heladeras: vendedor detrás, 1-3 clientes delante
    for kind in ("fruit_stand", "bread_stand", "freezer", "shop_shelf"):
        for it in out.get(kind, []):
            x, _, zz, yaw = it[0], it[1], it[2], it[3]
            fx, fz = math.sin(yaw), math.cos(yaw)
            crowd(x - fx * 0.9, zz - fz * 0.9, yaw)
            for q in range(int(1 + _frac(x, zz, 64) * 3)):
                crowd(x + fx * (1.1 + q * 0.8), zz + fz * (1.1 + q * 0.8), yaw + math.pi)
    # plazas y parques: kioscos de helado / comida con filas, y gente (Plaza de la República, mezquita)
    areas = [g for g in (getattr(squares, "geoms", [squares]) if not squares.is_empty else [])] + \
            [g for g in (getattr(parks, "geoms", [parks]) if not parks.is_empty else [])]
    for a in areas:
        if a.geom_type != "Polygon" or not rect.contains(a.centroid):
            continue
        n_people = int(min(140, a.area / 35))
        for (px, pz) in _pts_in(a, n_people, int(a.area)):
            crowd(px, pz, _frac(px, pz, 65) * 6.28)
        for (px, pz) in _pts_in(a.buffer(-3), max(1, int(a.area / 2500)), int(a.area) + 7):
            kind = ("ice_kiosk", "food_counter", "ice_cart", "ticket_kiosk", "truck", "truck")[int(_frac(px, pz, 66) * 6) % 6]
            yaw = _frac(pz, px, 67) * 6.28
            fx, fz = math.sin(yaw), math.cos(yaw)
            if kind == "truck":
                # camioneta de comida compuesta: furgón de reparto de costado, toldo y mostrador al frente
                Q.setdefault("van", []).append([px - fx * 1.6, Y, pz - fz * 1.6, yaw + math.pi / 2, 1.0])
                Q.setdefault("stall_roof", []).append([px - fx * 0.2, Y, pz - fz * 0.2, yaw, 1.0])
                Q["food_counter"].append([px + fx * 0.3, Y, pz + fz * 0.3, yaw, 1.0])
            else:
                Q[kind].append([px, Y, pz, yaw, 1.0])
            n_q = int(3 + _frac(px, pz, 68) * 5)
            for q in range(n_q):  # fila frente al mostrador
                crowd(px + fx * (2.0 + q * 0.75), pz + fz * (2.0 + q * 0.75), yaw + math.pi, "person_stand")
            Q["queue_post"].append([px + fx * 2.0 + fz * 0.7, Y, pz + fz * 2.0 - fx * 0.7, yaw, 1.0])
            Q["queue_post"].append([px + fx * (2.0 + n_q * 0.75) + fz * 0.7, Y, pz + fz * (2.0 + n_q * 0.75) - fx * 0.7, yaw, 1.0])
            Q.setdefault("bin", []).append([px + fz * 2.2, Y, pz - fx * 2.2, yaw, 1.0])
        for (px, pz) in _pts_in(a, int(a.area / 300), int(a.area) + 11):
            kind = ("palm_lean", "palm_young", "sea_grape", "pandanus")[int(_frac(px, pz, 69) * 4) % 4]
            Q[kind].append([px, DECK_Y, pz, _frac(px, pz, 70) * 6.28, 0.85 + _frac(pz, px, 71) * 0.3])
    # playa artificial: chicos jugando, bañistas, vegetación de playa
    if not beaches.is_empty:
        for (px, pz) in _pts_in(beaches, int(min(120, beaches.area / 60)), 9):
            if _frac(px, pz, 72) < 0.45:
                Q["person_kid"].append([px, 0.6, pz, _frac(px, pz, 73) * 6.28, 0.62 + _frac(pz, px, 74) * 0.12])
            else:
                crowd(px, pz, _frac(px, pz, 75) * 6.28)
                Q["person_stand" if _frac(px, pz, 76) < 0.5 else "person_talk"][-1][1] = 0.6
        for (px, pz) in _pts_in(beaches.buffer(4).difference(beaches).intersection(land), 30, 13):
            Q["palm_lean"].append([px, DECK_Y, pz, _frac(px, pz, 77) * 6.28, 1.0])
    # muelles: pasajeros esperando el ferry, bolardos y gaviotas en el borde, boyas cerca
    for pp in piers:
        if pp.is_empty:
            continue
        for (px, pz) in _pts_in(pp, int(min(60, pp.area / 25)), int(pp.area) + 3):
            crowd(px, pz, _frac(px, pz, 78) * 6.28)
        ring = pp.exterior if pp.geom_type == "Polygon" else pp.convex_hull.exterior
        n_b = int(ring.length / 6)
        for q in range(n_b):
            pt = ring.interpolate(q * 6.0)
            Q["bollard"].append([pt.x, DECK_Y - 0.3, pt.y, 0.0, 0.8])
            if _frac(pt.x, pt.y, 79) < 0.15:
                Q["seagull"].append([pt.x, DECK_Y - 0.3, pt.y, _frac(pt.y, pt.x) * 6.28, 1.0])
        for q in range(int(ring.length / 60)):
            pt = ring.interpolate(q * 60.0 + 25.0)
            c = pp.centroid
            dx, dz = pt.x - c.x, pt.y - c.y
            dl = math.hypot(dx, dz) or 1.0
            Q["buoy"].append([pt.x + dx / dl * 14, -0.2, pt.y + dz / dl * 14, 0.0, 0.8])
    # puerto de pesca: un pesquero amarrado y pescadores descargando junto al mercado
    mk = market_point(z)
    if mk is not None and rect.contains(Point(*mk)):
        Q["trawler"].append([mk[0] + 8.0, -0.1, mk[1] - 30.0, math.pi / 2, 1.0])
        for q in range(8):
            crowd(mk[0] + 2.0 + q * 1.4, mk[1] - 22.0 + (q % 3) * 0.8, math.pi, "person_stand")
    # veredas: parejas y grupos charlando (multitud estática), además de los peatones animados
    for hw, g, w, nm in road_info:
        if g.geom_type != "LineString" or hw in ("footway", "path"):
            continue
        for x, zz, dx, dz in _along(g, 17.0, 5.0):
            if _frac(x, zz, 80) < 0.45:
                continue
            sd = 1 if _frac(x, zz, 81) > 0.5 else -1
            nx, nz = dz, -dx
            px, pz = x + nx * (w / 2 + 0.9) * sd, zz + nz * (w / 2 + 0.9) * sd
            if not (rect.contains(Point(px, pz)) and land.contains(Point(px, pz))):
                continue
            yaw = math.atan2(dx, dz)
            crowd(px, pz, yaw, "person_talk")
            crowd(px + dx * 0.8, pz + dz * 0.8, yaw + math.pi)
    for k, lst in Q.items():
        for it in lst:  # mitad cuerpo femenino, mitad masculino
            kk = k + "_f" if k.startswith("person_") and _frac(it[0], it[2], 90) < 0.5 else k
            out[kk] = out.get(kk, []) + [[round(v, 3) for v in it]]
    print(z.id, "vida:", {k: len(v) for k, v in Q.items()})
    return out


def street_props(z, road_info, blds, parks, squares, land, rect, shop_lines):
    """Mobiliario urbano y detalle: [x, y, z, rumbo_rad, escala] por tipo (coordenadas locales).
    Malé: farolas en las calles con autos, motos estacionadas en racimos sobre el cordón (la ciudad
    tiene más motos que habitantes con licencia), algunos autos y pickups, bancos/cestos en
    parques y malecón, macetas y sillas frente a comercios, aires acondicionados y balcones en las
    fachadas que dan a la calle, árboles de vereda, y cables entre postes."""
    P = {k: [] for k in ("lamp", "scooter", "car", "bench", "bin", "chair", "plant", "ac", "balcony", "tree")
         + EXTRA_KINDS}
    signs = []
    from shapely.ops import unary_union as _uu
    road_near = _uu([g for _, g, _, _ in road_info]) if road_info else None
    cables = []
    bld_union = prep(unary_union([b["poly"] for b in blds]) if blds else Polygon())
    bld_buf = prep(unary_union([b["poly"].buffer(1.5) for b in blds]) if blds else Polygon())
    land = prep(land)
    rect = prep(rect)
    lamps_by_road = []
    for hw, g, w, nm in road_info:
        if not rect.intersects(g):
            continue
        veh = hw not in ("footway", "path", "pedestrian")
        side_off = w / 2 + 0.35
        row = []
        for x, zz, dx, dz in _along(g, 26.0 if veh else 40.0, 6.0):
            nx, nz = dz, -dx
            sd = 1 if _frac(x, zz) > 0.5 else -1
            px, pz = x + nx * side_off * sd, zz + nz * side_off * sd
            pt = Point(px, pz)
            if not rect.contains(pt) or not land.contains(pt) or bld_union.contains(pt):
                continue
            yaw = math.atan2(-nx * sd, -nz * sd)
            P["lamp"].append([px, DECK_Y, pz, yaw, 1.0])
            row.append((px, pz))
        if veh and len(row) > 1:
            lamps_by_road.append(row)
        if veh:
            # motos estacionadas en racimos sobre ambos cordones
            for x, zz, dx, dz in _along(g, 13.0, 3.0):
                f = _frac(x, zz, 1)
                if f < 0.4:
                    continue
                nx, nz = dz, -dx
                for sd in (-1, 1):
                    n_sc = int(2 + _frac(x, zz, sd) * (5 if hw in SHOP_ROADS else 3))
                    for k in range(n_sc):
                        t = (k - n_sc / 2) * 1.05
                        px = x + dx * t + nx * (w / 2 - 0.9) * sd
                        pz = zz + dz * t + nz * (w / 2 - 0.9) * sd
                        pt = Point(px, pz)
                        if rect.contains(pt) and land.contains(pt) and not bld_union.contains(pt):
                            yaw = math.atan2(nx * sd, nz * sd) + (_frac(px, pz) - 0.5) * 0.12
                            sk = TWO_WHEEL[int(_frac(px, pz, 21) * len(TWO_WHEEL)) % len(TWO_WHEEL)]
                            P[sk].append([px, DECK_Y + 0.02, pz, yaw, 1.0])
            if hw in SHOP_ROADS or hw in ("residential", "unclassified"):
                for x, zz, dx, dz in _along(g, 38.0, 17.0):
                    if _frac(x, zz, 2) < 0.55:
                        continue
                    nx, nz = dz, -dx
                    sd = 1 if _frac(x, zz, 3) > 0.5 else -1
                    px, pz = x + nx * (w / 2 - 1.2) * sd, zz + nz * (w / 2 - 1.2) * sd
                    if rect.contains(Point(px, pz)) and land.contains(Point(px, pz)):
                        f = _frac(px, pz)
                        kind = VEHICLES[int(f * len(VEHICLES)) % len(VEHICLES)]
                        P[kind].append([px, DECK_Y + 0.02, pz, math.atan2(dx, dz), 1.0])
            # cestos, conos, carteles y postes a lo largo de la vereda
            for x, zz, dx, dz in _along(g, 23.0, 7.0):
                nx, nz = dz, -dx
                sd = 1 if _frac(x, zz, 11) > 0.5 else -1
                px, pz = x + nx * (w / 2 + 0.5) * sd, zz + nz * (w / 2 + 0.5) * sd
                pt = Point(px, pz)
                if not (rect.contains(pt) and land.contains(pt)) or bld_union.contains(pt):
                    continue
                f = _frac(px, pz, 12)
                yaw = math.atan2(nx * sd, nz * sd)
                kind = ("bin" if f < 0.25 else "sign_street" if f < 0.35 else "elec_pole" if f < 0.47
                        else "planter" if f < 0.58 and hw in SHOP_ROADS else "hydrant" if f < 0.64
                        else "utility_box" if f < 0.72 else "trashbag" if f < 0.80 else "aframe" if f < 0.86 and hw in SHOP_ROADS
                        else "cone" if f < 0.805 else None)
                if kind:
                    P[kind].append([px, DECK_Y + 0.02, pz, yaw, 1.0])
                if kind == "bin":
                    P["trashbag"].append([px + dx * 0.7, DECK_Y + 0.02, pz + dz * 0.7, yaw + 1.0, 1.0])
                # tapa de alcantarilla en el medio de la calzada
                if _frac(x, zz, 17) < 0.35 and w > 4.0:
                    P["manhole"].append([x, DECK_Y + 0.035, zz, yaw, 1.0])
            # árboles de vereda (pocos: Malé es muy densa)
            for x, zz, dx, dz in _along(g, 31.0, 13.0):
                if _frac(x, zz, 4) < 0.6:
                    continue
                nx, nz = dz, -dx
                sd = -1 if _frac(x, zz, 5) > 0.5 else 1
                px, pz = x + nx * (w / 2 + 0.9) * sd, zz + nz * (w / 2 + 0.9) * sd
                pt = Point(px, pz)
                if rect.contains(pt) and land.contains(pt) and not bld_buf.contains(pt):
                    tk = ("tree", "frangipani", "banana_clump")[int(_frac(px, pz, 41) * 3) % 3]
                    P[tk].append([px, DECK_Y, pz, _frac(px, pz) * 6.28, 0.8 + _frac(pz, px) * 0.5])
    # cruces: semáforos en las calles principales, carteles de pare en las demás
    ends = {}
    for hw, g, w, nm in road_info:
        if hw in ("footway", "path", "pedestrian") or g.geom_type != "LineString":
            continue
        for c in (g.coords[0], g.coords[-1]):
            k = (round(c[0] / 3.0), round(c[1] / 3.0))
            ends.setdefault(k, []).append((hw, w, c))
    for k, lst in ends.items():
        if len(lst) < 3:
            continue
        cx, cz = lst[0][2]
        main = any(h in SHOP_ROADS for h, _, _ in lst)
        wmax = max(w for _, w, _ in lst)
        for q in range(2 if main else 1):
            a = q * math.pi + _frac(cx, cz, 13) * 0.5
            px, pz = cx + math.cos(a) * (wmax / 2 + 0.8), cz + math.sin(a) * (wmax / 2 + 0.8)
            pt = Point(px, pz)
            if rect.contains(pt) and land.contains(pt) and not bld_union.contains(pt):
                P["traffic_light" if main else "sign_stop"].append([px, DECK_Y + 0.02, pz, a + math.pi / 2, 1.0])
    # cables: entre farolas consecutivas, y cruzando la calle cada tanto (catenaria en el juego)
    for row in lamps_by_road:
        for a, b in zip(row, row[1:]):
            if math.dist(a, b) < 45.0:
                cables.append([a[0], DECK_Y + 6.8, a[1], b[0], DECK_Y + 6.8, b[1]])
    # bancos, cestos: parques y plazas
    for poly in [g for g in (list(parks.geoms) if hasattr(parks, "geoms") else [parks])
                 + (list(squares.geoms) if hasattr(squares, "geoms") else [squares]) if not g.is_empty]:
        if poly.geom_type != "Polygon":
            continue
        ring = poly.exterior
        for x, zz, dx, dz in _along(ring, 14.0, 4.0):
            nx, nz = -dz, dx
            px, pz = x + nx * 1.2, zz + nz * 1.2
            if not poly.contains(Point(px, pz)):
                px, pz, nx, nz = x - nx * 1.2, zz - nz * 1.2, -nx, -nz
            if not rect.contains(Point(px, pz)):
                continue
            kind = "bin" if _frac(px, pz, 6) < 0.3 else "bench"
            P[kind].append([px, DECK_Y + 0.03, pz, math.atan2(nx, nz), 1.0])
    # frentes de edificios: comercios (macetas, sillas), aires acondicionados y balcones
    for b in blds:
        g = b["poly"]
        if b["kind"] != "building" or g.geom_type != "Polygon":
            continue
        floors = max(1, int((b["h"] - 1.0) / FLOOR_H))
        ext = list(g.exterior.coords)
        for a in range(len(ext) - 1):
            p0, p1 = ext[a], ext[a + 1]
            L = math.dist(p0, p1)
            if L < 4.0:
                continue
            mx, mz = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
            ux, uz = (p1[0] - p0[0]) / L, (p1[1] - p0[1]) / L
            nx, nz = uz, -ux
            if g.contains(Point(mx + nx * 0.5, mz + nz * 0.5)):
                nx, nz = -nx, -nz
            front = Point(mx + nx * 3.0, mz + nz * 3.0)
            if bld_union.contains(front) or not rect.contains(Point(mx, mz)):
                continue  # pared medianera o contra otro edificio: sin detalle
            if road_near is not None and front.distance(road_near) > 9.0:
                continue  # patio interior: sin balcones ni aires (se veían sueltos en los patios)
            yaw = math.atan2(nx, nz)
            street = shop_lines is not None and not shop_lines.is_empty and Point(mx, mz).distance(shop_lines) < 12.0
            n_cell = int(L // 3.0)
            for c in range(n_cell):
                t = (c + 0.5) * 3.0 - n_cell * 1.5 + L / 2
                cx, cz = p0[0] + ux * t, p0[1] + uz * t
                for fl in range(1, floors):
                    f = _frac(cx, cz, fl)
                    y = DECK_Y + fl * FLOOR_H
                    if f < 0.16:
                        P["balcony"].append([cx + nx * 0.05, y, cz + nz * 0.05, yaw, 1.0])
                    elif f < 0.34:
                        P["ac"].append([cx + nx * 0.05 + ux * 1.0, y + 0.55, cz + nz * 0.05 + uz * 1.0, yaw, 1.0])
                if street and c % 3 == 0 and _frac(cx, cz, 31) < 0.7:
                    # letrero de comercio (atlas de 16, Dhivehi/inglés) sobre la vidriera
                    signs.append([round(cx + nx * 0.12, 3), round(DECK_Y + FLOOR_H - 0.55, 3), round(cz + nz * 0.12, 3),
                                  round(yaw, 4), int(_frac(cz, cx, 32) * 16) % 16])
                if street and c % 3 == 1:
                    f = _frac(cx, cz, 9)
                    if f < 0.25:
                        P["plant"].append([cx + nx * 0.6, DECK_Y + 0.03, cz + nz * 0.6, yaw, 1.0])
                    elif f < 0.40:
                        kind = SHOP_FRONT[int(_frac(cz, cx, 14) * len(SHOP_FRONT)) % len(SHOP_FRONT)]
                        P[kind].append([cx + nx * 0.8, DECK_Y + 0.03, cz + nz * 0.8, yaw + math.pi, 1.0])
                        if kind == "fruit_stand":
                            P["bananas"].append([cx + nx * 0.8, DECK_Y + 1.05, cz + nz * 0.8, yaw, 1.0])
                    elif f < 0.46:
                        P["cafe_table"].append([cx + nx * 1.6, DECK_Y + 0.03, cz + nz * 1.6, yaw, 1.0])
                        for k in (-0.7, 0.7):
                            P["stool"].append([cx + nx * 1.6 + ux * k, DECK_Y + 0.03, cz + nz * 1.6 + uz * k, yaw, 1.0])
                    elif f < 0.52:
                        for k in (-0.5, 0.5):
                            P["chair"].append([cx + nx * 0.9 + ux * k, DECK_Y + 0.03, cz + nz * 0.9 + uz * k,
                                               yaw + math.pi, 1.0])
    # azoteas: tanques de agua y antenas (casi todas las azoteas de Malé tienen alguno)
    for b in blds:
        g = b["poly"]
        if g.geom_type != "Polygon" or g.area < 40 or not rect.contains(g.centroid):
            continue
        c = g.representative_point()
        f = _frac(c.x, c.y, 15)
        y = DECK_Y + b["h"] - 1.0 + 0.05
        if f < 0.55:
            P["roof_tank"].append([c.x, y, c.y, f * 12.0, 1.0])
        if 0.6 < f < 0.8 and g.area > 70:
            P["laundry"].append([c.x + 1.5, y, c.y - 1.0, f * 7.0, 1.0])
        if 0.3 < f < 0.75:
            q = g.buffer(-1.5)
            if not q.is_empty:
                p2 = q.exterior.interpolate(_frac(c.y, c.x, 16) * q.exterior.length) if q.geom_type == "Polygon" else c
                P["antenna"].append([p2.x, y, p2.y, f * 9.0, 1.0])
    # mercado de pescado y frutas (Malé, frente al puerto norte, ~73.5087 E 4.1781 N)
    mk = market_point(z)
    if mk is not None and rect.contains(Point(*mk)):
        for r_ in range(4):
            for c_ in range(6):
                px, pz = mk[0] + c_ * 3.2, mk[1] + r_ * 4.0
                if not land.contains(Point(px, pz)) or bld_union.contains(Point(px, pz)):
                    continue
                P["stall_roof"].append([px, DECK_Y + 0.02, pz, 0.0, 1.0])
                P["fruit_stand" if (r_ + c_) % 3 else "fish_crate"].append([px, DECK_Y + 0.03, pz, 0.0, 1.0])
                P["crate"].append([px + 1.2, DECK_Y + 0.03, pz + 0.9, _frac(px, pz) * 3.0, 1.0])
                P["wood_crate"].append([px - 1.1, DECK_Y + 0.03, pz + 1.2, _frac(pz, px) * 3.0, 1.0])
                P["bananas"].append([px, DECK_Y + 1.05, pz, _frac(px, pz, 3) * 6.0, 1.0])
        # puerto comercial: contenedores apilados y una grúa
        for q in range(12):
            px, pz = mk[0] - 30.0 + (q % 4) * 6.6, mk[1] - 18.0 - (q // 4) * 2.6
            if land.contains(Point(px, pz)) and not bld_union.contains(Point(px, pz)):
                P["container"].append([px, DECK_Y + 0.02 + (2.6 if q % 5 == 0 else 0.0), pz, math.pi / 2, 1.0])
        P["crane"].append([mk[0] - 40.0, DECK_Y + 0.02, mk[1] - 22.0, 0.6, 1.0])
        for q in range(10):
            P["tyre" if q % 2 else "barrier"].append([mk[0] - 6.0 + q * 2.4, DECK_Y + 0.03, mk[1] - 5.0, 0.0, 1.0])
    out = {k: [[round(v, 3) for v in it] for it in lst] for k, lst in P.items()}
    out["shop_signs"] = signs
    out["cables"] = [[round(v, 2) for v in c] for c in cables]
    print(z.id, "detalle urbano:", {k: len(v) for k, v in out.items()})
    return out


def npc_paths(road_info, land, rect, blds):
    """Recorridos para NPC: veredas (peatones) y carriles (motos), en coordenadas locales."""
    bld_union = unary_union([b["poly"].buffer(0.3) for b in blds]) if blds else Polygon()
    walk, ride = [], []
    for hw, g, w, nm in road_info:
        if g.length < 40.0 or not g.intersects(rect):
            continue
        veh = hw not in ("footway", "path", "pedestrian")
        for off in ((w / 2 + 0.8, -(w / 2 + 0.8)) if veh else (0.0,)):
            try:
                lg = g.parallel_offset(abs(off), "left" if off >= 0 else "right") if off else g
            except Exception:
                continue
            lg = lg.intersection(rect).intersection(land).difference(bld_union)
            for part in (lg.geoms if hasattr(lg, "geoms") else [lg]):
                if part.geom_type == "LineString" and part.length > 30.0:
                    walk.append([[round(c[0], 2), round(c[1], 2)] for c in part.simplify(0.5).coords])
        if veh and hw != "service":
            lg = g.intersection(rect).intersection(land)
            for part in (lg.geoms if hasattr(lg, "geoms") else [lg]):
                if part.geom_type == "LineString" and part.length > 60.0:
                    ride.append([[round(c[0], 2), round(c[1], 2)] for c in part.simplify(0.5).coords])
    return {"walk": walk[:400], "ride": ride[:150]}


def boat_points(land_all, rect):
    """Dhonis y lanchas fondeadas cerca de la costa (puerto y malecón)."""
    sea = rect.difference(land_all)
    ring = land_all.buffer(35.0).difference(land_all.buffer(12.0)).intersection(sea)
    pts = []
    x0, z0, x1, z1 = rect.bounds
    zz = z0
    while zz < z1:
        x = x0
        while x < x1:
            p = Point(x, zz)
            if ring.contains(p) and _frac(x, zz, 7) < 0.5:
                d = land_all.exterior.project(p) if land_all.geom_type == "Polygon" else 0.0
                q = land_all.exterior.interpolate(d) if land_all.geom_type == "Polygon" else p
                yaw = math.atan2(p.x - q.x, p.y - q.y) + math.pi / 2
                pts.append([round(x, 1), 0.0, round(zz, 1), round(yaw, 3), 1.0 if _frac(zz, x) < 0.6 else 1.4])
            x += 45.0
        zz += 45.0
    return pts[:60]


def palm_points(parks, squares, sidewalks, road_info, z):
    pts = []
    for p in (parks.geoms if hasattr(parks, "geoms") else [parks]):
        if p.is_empty or p.geom_type != "Polygon":
            continue
        x0, y0, x1, y1 = p.bounds
        step = 9.0
        x = x0
        while x < x1:
            y = y0
            while y < y1:
                s = hh((round(x), round(y)))
                q = Point(x + (s % 50) / 10.0, y + (s // 50 % 50) / 10.0)
                if p.buffer(-1.5).contains(q):
                    pts.append([q.x, q.y, (s % 360), 0.85 + (s % 30) / 100.0])
                y += step
            x += step
    return pts[:900]


def main():
    if "--fetch" in sys.argv or not (RAW / "osm_male.json").exists():
        fetch_male()
    osm = load_osm()
    print("OSM Malé:", {k: len(v) for k, v in osm.items()})
    _, nmid = lonlat_to_global(73.515, 4.177)
    k = k_at(nmid)
    l8 = L8()
    metas = []
    for spec in (ZONE_W, ZONE_E):
        z = Zone(spec, k)
        metas.append(build_zone(z, osm, l8, REPO / "data" / "sites" / z.id))
    # recorrido de prueba: Majeedhee Magu cruzando el borde oeste/este (-70 m .. +50 m)
    mj = linemerge([it["line_ll"] for it in osm["roads"] if it["tags"].get("name") == "Majeedhee Magu"
                    or it["tags"].get("name:en") == "Majeedhee Magu"])
    zg = Zone(ZONE_W, k)
    lines = mj.geoms if hasattr(mj, "geoms") else [mj]
    border_x = zg.w
    walk = None
    for ln in lines:
        lg = to_local_geom(ln, zg)
        if lg.bounds[0] < border_x < lg.bounds[2]:
            cut = lg.intersection(LineString([(border_x, -1e4), (border_x, 1e4)]))
            if cut.is_empty:
                continue
            p0 = cut if cut.geom_type == "Point" else list(cut.geoms)[0]
            s0 = lg.project(p0)
            pts = [lg.interpolate(s0 + d) for d in range(-70, 55, 5)]
            if pts[0].x > pts[-1].x:
                pts = [lg.interpolate(s0 - d) for d in range(-70, 55, 5)]
            walk = [[zg.e0 + p.x * k, zg.n0 - p.y * k] for p in pts]
            break
    # métricas de lo caminable (isla completa, ambas zonas)
    land_ll = island_polygon(osm)
    zl = Zone((None, None, 73.4975, 4.1880, 73.5320, 4.1655), k)
    land_all_l = to_local_geom(land_ll, zl).intersection(zl.rect)
    # solo la isla de Malé (el rectángulo también toca Funadhoo y la punta de Hulhulé)
    mp = zl.to_local(73.510, 4.175)
    parts = land_all_l.geoms if hasattr(land_all_l, "geoms") else [land_all_l]
    land_l = next((g for g in parts if g.buffer(30).contains(Point(mp))), land_all_l)
    road_len = 0.0
    road_polys = []
    for it in osm["roads"]:
        g = to_local_geom(it["line_ll"], zl)
        gi = g.intersection(land_l.buffer(15))
        road_len += gi.length
        road_polys.append(g.buffer(ROAD_W[it["tags"]["highway"]] / 2 + SIDEWALK_W, cap_style=2))
    streets_area = unary_union(road_polys).intersection(land_l).area
    beach_a = sum(to_local_geom(it["poly_ll"], zl).intersection(zl.rect).area for it in osm["beaches"] if "poly_ll" in it)
    pier_a = sum(to_local_geom(it["poly_ll"], zl).difference(land_l).intersection(land_l.buffer(400)).area
                 for it in osm["piers"] if "poly_ll" in it)
    metrics = {"street_length_km": round(road_len / 1000, 2), "street_area_km2": round(streets_area / 1e6, 3),
               "walkable_ground_km2": round((land_l.area + pier_a) / 1e6, 3),
               "beach_area_m2": round(beach_a), "pier_area_m2": round(pier_a),
               "island_bbox_m": [round(x) for x in land_l.bounds]}
    print("métricas:", metrics)
    (REPO / "data" / "sites" / "male_metrics.json").write_text(json.dumps(metrics, indent=1))
    (REPO / "data" / "sites" / "male_test_walk.json").write_text(json.dumps({"street": "Majeedhee Magu", "points": walk}))
    (REPO / "data" / "sites" / "male_zones.json").write_text(json.dumps(
        [{"id": m["id"], "name": m["name"], "origin": m["origin_global"], "size_local": m["size"], "k": m["k"]}
         for m in metas], indent=1))


if __name__ == "__main__":
    main()
