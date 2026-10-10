#!/usr/bin/env python3
"""Micro-mapa de un resort real de Atolón Malé Norte: la isla Lankanfinolhu (~13 km al NE de Malé).

Todo sale de OpenStreetMap (ODbL): costa del islote, edificios en tierra, muelles (man_made=pier)
y las villas sobre el agua (edificios OSM cuyo centroide cae fuera de la isla). No se usa el nombre
comercial del resort en el juego: la zona se llama por el nombre de la isla.

Salida en data/sites/mv_lankanfinolhu/ con el mismo formato que make_male.py (VMM1 + meta.json +
depth.f32) para que tools/gen_male.gd arme la escena con estilo "resort".
"""
import json
import math
import sys
import urllib.parse
import urllib.request

import numpy as np
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union, nearest_points

from make_male import L8, Mesh, Zone, hh, k_at, to_local_geom, walls_of, load_osm_file, boat_points
from vm_common import RAW, REPO, lonlat_to_global

ZONE = ("mv_lankanfinolhu", "Lankanfinolhu (resort)", 73.5480, 4.3010, 73.5665, 4.2785)
BBOX = (73.535, 4.270, 73.570, 4.305)
OSM_FILE = "osm_lankanfinolhu.json"
GROUND_Y = 1.4      # arena de la isla
DECK_Y = 2.6        # muelles y terrazas de villas (sobre pilotes)
VILLA_H = 3.4       # altura de pared de villa
LAND_BLD_H = 4.2
JETTY_W = 2.4
TERRACE = 3.5       # terraza alrededor de cada villa


def fetch():
    q = ("[out:json][timeout:120];(way({1},{0},{3},{2});relation({1},{0},{3},{2}););out body geom;"
         .format(*BBOX))
    for m in ("https://overpass-api.de/api/interpreter", "https://maps.mail.ru/osm/tools/overpass/api/interpreter"):
        try:
            req = urllib.request.Request(m, data=urllib.parse.urlencode({"data": q}).encode(),
                                         headers={"User-Agent": "vuelo-mundo-pipeline/0.2"})
            with urllib.request.urlopen(req, timeout=200) as r:
                (RAW / OSM_FILE).write_bytes(r.read())
                return
        except Exception as e:  # noqa: BLE001
            print("Overpass falló", m, e)
    raise SystemExit("sin datos OSM")


def hip_roof(poly, y0, rise, mesh):
    """Techo a cuatro aguas aproximado: abanico desde el centroide (paja)."""
    p = poly.simplify(0.3)
    if p.geom_type != "Polygon":
        return
    c = p.centroid
    ext = list(p.exterior.coords)
    if not p.exterior.is_ccw:
        ext = ext[::-1]
    for a in range(len(ext) - 1):
        (x0, z0), (x1, z1) = ext[a], ext[a + 1]
        # alero: 0.6 m hacia afuera
        def out(x, z):
            dx, dz = x - c.x, z - c.y
            L = math.hypot(dx, dz) or 1.0
            return (x + dx / L * 0.6, y0 - 0.25, z + dz / L * 0.6)
        v0, v1, top = out(x0, z0), out(x1, z1), (c.x, y0 + rise, c.y)
        n = np.cross(np.subtract(v1, v0), np.subtract(top, v0))
        if n[1] < 0:
            v0, v1 = v1, v0
            n = -n
        n = n / (np.linalg.norm(n) or 1.0)
        # orden horario visto desde la normal (convención Godot de make_male)
        mesh.add_tri_list([v0, top, v1], [tuple(n)] * 3)
        mesh.add_tri_list([v0, v1, top], [tuple(-n)] * 3)  # cara inferior (alero visto desde abajo)


def openings(g, y0, toward, meshes):
    """Ventanales (vidrio oscuro con marco) y una puerta en la cara que mira al muelle/sendero."""
    ext = list(g.exterior.coords)
    if g.exterior.is_ccw:
        ext = ext[::-1]
    best, best_d = None, 1e9
    edges = []
    for a in range(len(ext) - 1):
        p0, p1 = ext[a], ext[a + 1]
        L = math.dist(p0, p1)
        if L < 2.2:
            continue
        nx, nz = (p1[1] - p0[1]) / L, -(p1[0] - p0[0]) / L
        mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
        if g.contains(Point(mid[0] + nx * 0.3, mid[1] + nz * 0.3)):
            nx, nz = -nx, -nz
            p0, p1 = p1, p0
        edges.append((p0, p1, L, nx, nz, mid))
        d = Point(mid).distance(toward) if toward is not None and not toward.is_empty else 0.0
        if d < best_d:
            best, best_d = len(edges) - 1, d
    for k, (p0, p1, L, nx, nz, mid) in enumerate(edges):
        ux, uz = (p1[0] - p0[0]) / L, (p1[1] - p0[1]) / L
        o = 0.05
        if k == best:
            w, h = 1.0, 2.1
            col = "frames"
        else:
            w, h = min(L * 0.7, 4.5), 2.0
            col = "glass"
        a = (mid[0] - ux * w / 2 + nx * o, mid[1] - uz * w / 2 + nz * o)
        b = (mid[0] + ux * w / 2 + nx * o, mid[1] + uz * w / 2 + nz * o)
        # marco: un poco más grande y apenas detrás
        fa = (mid[0] - ux * (w / 2 + 0.08) + nx * (o - 0.01), mid[1] - uz * (w / 2 + 0.08) + nz * (o - 0.01))
        fb = (mid[0] + ux * (w / 2 + 0.08) + nx * (o - 0.01), mid[1] + uz * (w / 2 + 0.08) + nz * (o - 0.01))
        yb = y0 + (0.0 if k == best else 0.35)
        if k != best:
            meshes["frames"].add_quad(fb, fa, yb - 0.08, yb + h + 0.08)
            meshes["frames"].add_quad(fa, fb, yb - 0.08, yb + h + 0.08)
        meshes[col].add_quad(b, a, yb, yb + h)
        meshes[col].add_quad(a, b, yb, yb + h)


def posts_along(line, mesh, w, y_top, step=3.0):
    """Pilotes de madera a ambos lados de un muelle/terraza."""
    L = line.length
    s = 0.0
    while s <= L:
        p = line.interpolate(s)
        q = line.interpolate(min(L, s + 0.5))
        dx, dz = q.x - p.x, q.y - p.y
        n = math.hypot(dx, dz) or 1.0
        px, pz = -dz / n, dx / n
        for side in (-1, 1):
            cx, cz = p.x + px * side * (w / 2 - 0.15), p.y + pz * side * (w / 2 - 0.15)
            sq = box(cx - 0.09, cz - 0.09, cx + 0.09, cz + 0.09)
            walls_of(sq, -2.5, y_top - 0.15, mesh, (0.55, 0.42, 0.3, 1))
        s += step


def ladder(x, z, nx, nz, mesh):
    """Escalera de la terraza a la laguna: dos largueros y peldaños cada 0.35 m."""
    px, pz = -nz, nx
    for side in (-0.3, 0.3):
        cx, cz = x + px * side, z + pz * side
        walls_of(box(cx - 0.03, cz - 0.03, cx + 0.03, cz + 0.03), -1.2, DECK_Y + 0.9, mesh, (0.75, 0.77, 0.8, 1))
    y = -1.0
    while y < DECK_Y:
        a = (x - px * 0.3, z - pz * 0.3)
        b = (x + px * 0.3, z + pz * 0.3)
        seg = LineString([a, b]).buffer(0.025, cap_style=2)
        walls_of(seg, y, y + 0.05, mesh, (0.75, 0.77, 0.8, 1))
        y += 0.35


def main():
    if "--fetch" in sys.argv or not (RAW / OSM_FILE).exists():
        fetch()
    osm = load_osm_file(OSM_FILE)
    _, nmid = lonlat_to_global(73.556, 4.29)
    z = Zone(ZONE, k_at(nmid))
    rect = z.rect
    loc = lambda g: to_local_geom(g, z)  # noqa: E731
    js = json.loads((RAW / OSM_FILE).read_text())
    isl = []
    for el in js["elements"]:
        t = el.get("tags", {})
        if el["type"] == "way" and t.get("place") == "islet" and t.get("name") == "Lankanfinolhu":
            isl.append(Polygon([(p["lon"], p["lat"]) for p in el["geometry"]]).buffer(0))
    land = loc(unary_union(isl)).buffer(0).intersection(rect)
    if land.geom_type == "MultiPolygon":
        land = max(land.geoms, key=lambda g: g.area)
    out_dir = REPO / "data" / "sites" / z.id
    out_dir.mkdir(parents=True, exist_ok=True)
    meshes = {k: Mesh() for k in ("deck", "beach", "sidewalk", "park", "pier", "stilts", "walls",
                                  "roofs", "thatch", "seabed", "glass", "frames")}

    # isla: anillo de playa (25 m) en rampa hacia el agua + interior de arena/jardín
    inner = land.buffer(-25.0)
    beach = land.difference(inner)
    inner_b = inner.boundary

    def beach_y(x, zz):
        d = Point(x, zz).distance(inner_b)
        return GROUND_Y - min(1.0, d / 25.0) * (GROUND_Y + 0.9)
    # bandas concéntricas cada 5 m: la pendiente queda suave (vértices intermedios reales)
    for d0 in range(0, 25, 5):
        band = land.buffer(-d0).difference(land.buffer(-(d0 + 5)))
        meshes["beach"].add_poly(band.segmentize(5.0), 0.0, 1 / 3, y_fn=beach_y)

    paths = [loc(it["line_ll"]) for it in osm["roads"] if "line_ll" in it]
    path_poly = unary_union([g.buffer(1.3, cap_style=2) for g in paths]).intersection(inner) if paths else Polygon()

    # edificios: en tierra (pabellones) y sobre el agua (villas en pilotes)
    land_blds, villas = [], []
    for it in osm["buildings"]:
        g = loc(it["poly_ll"]).buffer(0)
        if g.is_empty or g.geom_type != "Polygon" or not rect.contains(g.centroid) or g.area < 12:
            continue
        (land_blds if land.buffer(5).contains(g.centroid) else villas).append((it, g))

    # muelles: líneas OSM -> pasarelas de 2.4 m; polígonos tal cual
    jetty_lines, jetty_polys = [], []
    for it in osm["piers"]:
        g = loc(it.get("poly_ll") or it["line_ll"])
        if not g.intersects(rect):
            continue
        if g.geom_type == "LineString":
            jetty_lines.append(g)
            jetty_polys.append(g.buffer(JETTY_W / 2, cap_style=2, join_style=2))
        else:
            jetty_polys.append(g)
    # OSM a veces dibuja villas encima de la pasarela: la pasarela manda (se recorta la villa)
    jet0 = unary_union(jetty_polys).buffer(0.4) if jetty_polys else Polygon()
    trimmed = []
    for it, g in villas:
        g2 = g.difference(jet0)
        if g2.geom_type == "MultiPolygon":
            g2 = max(g2.geoms, key=lambda q: q.area)
        if g2.geom_type == "Polygon" and g2.area > 12:
            trimmed.append((it, g2))
    villas = trimmed
    terr = []
    ladders = []
    for it, g in villas:
        t = g.buffer(TERRACE, join_style=2)
        terr.append(t)
        # escalera en la cara más lejana del muelle
        far = max(list(t.exterior.coords), key=lambda c: Point(c).distance(unary_union(jetty_lines) if jetty_lines else land))
        cx, cz = g.centroid.x, g.centroid.y
        nx, nz = far[0] - cx, far[1] - cz
        n = math.hypot(nx, nz) or 1.0
        nx, nz = nx / n, nz / n
        ladders.append((cx + nx * (t.exterior.distance(Point(cx, cz)) - 0.2) if False else far[0] - nx * 0.3,
                        far[1] - nz * 0.3, nx, nz))
    # pasarela corta de cada villa al muelle más cercano (si OSM no la mapea)
    jet_u = unary_union(jetty_polys) if jetty_polys else Polygon()
    spurs = []
    for t in terr:
        if not jet_u.is_empty and not t.intersects(jet_u):
            a, b = nearest_points(t, jet_u)
            if a.distance(b) < 25.0:
                spurs.append(LineString([a, b]).buffer(0.9, cap_style=2).union(b.buffer(0.9)).union(a.buffer(0.9)))
    over = unary_union(jetty_polys + terr + spurs).difference(land).intersection(rect)
    walk_deck = over.difference(unary_union([g for _, g in villas]))
    meshes["pier"].add_poly(walk_deck, DECK_Y, 1 / 2.5)
    walls_of(over, DECK_Y - 0.3, DECK_Y, meshes["stilts"], (0.6, 0.47, 0.34, 1))  # canto del deck
    for ln in jetty_lines:
        seg = ln.difference(land)
        for s in (seg.geoms if hasattr(seg, "geoms") else [seg]):
            if s.geom_type == "LineString" and s.length > 2:
                posts_along(s, meshes["stilts"], JETTY_W, DECK_Y, 3.0)
    for t in terr:
        for c in list(t.exterior.coords)[:-1]:
            walls_of(box(c[0] - 0.14, c[1] - 0.14, c[0] + 0.14, c[1] + 0.14), -2.5, DECK_Y - 0.15,
                     meshes["stilts"], (0.55, 0.42, 0.3, 1))
    for (x, zz, nx, nz) in ladders:
        ladder(x, zz, nx, nz, meshes["stilts"])

    # mobiliario de terrazas: dos reposeras y una sombrilla del lado de la laguna
    props = {"lounger": [], "parasol": [], "plant": []}
    deck_safe = walk_deck.buffer(-0.5)
    for it, g in villas:
        c = g.centroid
        a, b = nearest_points(g, jet_u) if not jet_u.is_empty else (c, c)
        dx, dz = c.x - b.x, c.y - b.y
        n = math.hypot(dx, dz) or 1.0
        dx, dz = dx / n, dz / n
        px, pz = -dz, dx
        hit = LineString([(c.x, c.y), (c.x + dx * 60, c.y + dz * 60)]).intersection(g.exterior)
        r = min((c.distance(q) for q in (hit.geoms if hasattr(hit, "geoms") else [hit]) if not q.is_empty),
                default=3.0)
        yaw = math.atan2(-dx, -dz)
        for side in (-0.9, 0.9):
            q = Point(c.x + dx * (r + 1.3) + px * side, c.y + dz * (r + 1.3) + pz * side)
            if deck_safe.contains(q):
                props["lounger"].append([round(q.x, 2), DECK_Y, round(q.y, 2), round(yaw, 3), 1.0])
        q = Point(c.x + dx * (r + 1.6) + px * 2.4, c.y + dz * (r + 1.6) + pz * 2.4)
        if deck_safe.contains(q):
            props["parasol"].append([round(q.x, 2), DECK_Y, round(q.y, 2), 0.0, 1.0])
        q = Point(a.x + (b.x - a.x) * 0.5 + px * 1.2, a.y + (b.y - a.y) * 0.5 + pz * 1.2)
        if deck_safe.contains(q):
            props["plant"].append([round(q.x, 2), DECK_Y, round(q.y, 2), 0.0, 1.0])
    # playa: reposeras y sombrillas cada ~22 m sobre la arena alta
    ring = land.buffer(-15.0).exterior
    s_ = 0.0
    while s_ < ring.length:
        q = ring.interpolate(s_)
        q2 = ring.interpolate(s_ + 1.0)
        nx, nz = -(q2.y - q.y), (q2.x - q.x)
        yaw = math.atan2(nx, nz)
        props["parasol"].append([round(q.x, 2), beach_y(q.x, q.y), round(q.y, 2), 0.0, 1.0])
        for off in (-1.2, 1.2):
            qq = ring.interpolate(s_ + off)
            props["lounger"].append([round(qq.x, 2), beach_y(qq.x, qq.y), round(qq.y, 2), round(yaw, 3), 1.0])
        s_ += 22.0

    # interior: senderos de arena compacta, jardín tropical y suelo de arena
    blds_all = unary_union([g.buffer(0.5) for _, g in land_blds]) if land_blds else Polygon()
    garden = inner.difference(path_poly).difference(blds_all).buffer(-4.0).buffer(2.0).intersection(inner)
    meshes["deck"].add_poly(inner.difference(garden), GROUND_Y, 1 / 3)
    meshes["park"].add_poly(garden, GROUND_Y + 0.02, 1 / 4)
    meshes["sidewalk"].add_poly(path_poly, GROUND_Y + 0.03, 1 / 2)

    for it, g in land_blds:
        y1 = GROUND_Y + LAND_BLD_H + (hh(it["id"]) % 2) * 1.5
        walls_of(g, GROUND_Y - 0.2, y1, meshes["walls"], (0.96, 0.94, 0.9, 1), (2.0, 0.0))
        openings(g, GROUND_Y, path_poly, meshes)
        meshes["roofs"].add_poly(g, y1, 1 / 4)
        hip_roof(g, y1 + 0.05, min(4.0, 0.25 * math.sqrt(g.area) + 1.0), meshes["thatch"])
    for it, g in villas:
        y1 = DECK_Y + VILLA_H
        walls_of(g, DECK_Y - 0.05, y1, meshes["walls"], (0.93, 0.88, 0.8, 1), (2.0, 0.0))
        openings(g, DECK_Y, jet_u, meshes)
        meshes["roofs"].add_poly(g, y1, 1 / 4)
        hip_roof(g, y1 + 0.05, min(3.5, 0.3 * math.sqrt(g.area) + 1.0), meshes["thatch"])

    # palmeras: muchas, en jardín y bordeando la playa, ligeramente inclinadas hacia el mar
    palms = []
    rng = np.random.default_rng(7)
    minx, minz, maxx, maxz = inner.bounds
    tries = 0
    while len(palms) < 900 and tries < 30000:
        tries += 1
        x, zz = rng.uniform(minx, maxx), rng.uniform(minz, maxz)
        p = Point(x, zz)
        if not inner.buffer(8).contains(p) or blds_all.buffer(2.0).contains(p) or path_poly.buffer(0.8).contains(p):
            continue
        palms.append([round(x, 2), round(zz, 2), float(rng.uniform(0, 360)), round(float(rng.uniform(0.8, 1.25)), 2)])

    # agua: laguna turquesa poco profunda alrededor (villas sobre 1.5-3 m), cae a L8 lejos
    l8 = L8()
    N = 192
    depth = np.zeros((N, N), np.float32)
    coast = land.boundary
    edge = rect.exterior
    for r in range(N):
        for c in range(N):
            x, zz = c / (N - 1) * z.w, r / (N - 1) * z.h
            p = Point(x, zz)
            if land.buffer(-25.0).contains(p):
                depth[r, c] = -1.0
                continue
            if land.contains(p):
                depth[r, c] = -0.2
                continue
            dl8 = max(l8.depth(z.e0 + x * z.k, z.n0 - zz * z.k), 1.0)
            dc = p.distance(coast)
            # plataforma de arrecife: 1-4 m hasta ~250 m de la costa, luego se funde con L8
            shelf = 0.8 + min(dc, 250.0) * 0.012
            t = min(1.0, max(0.0, (dc - 250.0) / 350.0))
            t = t * t * (3 - 2 * t)
            model = shelf * (1 - t) + max(dl8, shelf) * t
            we = max(0.0, 1.0 - p.distance(edge) / 250.0)
            depth[r, c] = model * (1 - we) + dl8 * we
    depth.tofile(out_dir / "depth.f32")
    G = 64
    for r in range(G - 1):
        for c in range(G - 1):
            quad = []
            for (rr, cc) in ((r, c), (r, c + 1), (r + 1, c + 1), (r + 1, c)):
                x, zz = cc / (G - 1) * z.w, rr / (G - 1) * z.h
                d = depth[min(N - 1, round(rr / (G - 1) * (N - 1))), min(N - 1, round(cc / (G - 1) * (N - 1)))]
                quad.append((x, -max(d, 0.5) if d > -0.5 else -0.5, zz))
            meshes["seabed"].add_tri_list([quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]], [(0, 1, 0)] * 6)

    stats = {name: m.write(out_dir / f"{name}.vmm") for name, m in meshes.items() if m.i}

    # recorrido de prueba: aterrizar en la terraza de la villa más lejana de un muelle largo y
    # caminar por el muelle hacia la isla
    parts = []
    for ln in jetty_lines:
        seg = ln.difference(land)
        parts += [g for g in (seg.geoms if hasattr(seg, "geoms") else [seg]) if g.geom_type == "LineString"]
    safe = walk_deck.buffer(-0.45)
    cands = sorted(((v, seg) for seg in parts if seg.length >= 120 for v in villas if v[1].distance(seg) < 8.0),
                   key=lambda c: -c[0][1].distance(land))
    walk = None
    landing = None
    for v, seg in cands:
        a, b = nearest_points(v[1], seg)
        dd = a.distance(b) or 1.0
        off = min(1.6, dd * 0.5)
        lp = Point(a.x + (b.x - a.x) / dd * off, a.y + (b.y - a.y) / dd * off)  # terraza, frente a la puerta
        s0 = seg.project(lp)
        sgn = 1 if s0 < seg.length - 80 else -1
        pts = [lp] + [seg.interpolate(s0 + sgn * d) for d in range(0, 80, 5)]
        path = LineString([(p.x, p.y) for p in pts])
        if all(safe.contains(path.interpolate(d)) for d in np.arange(0.0, path.length, 0.5)):
            landing = [z.e0 + lp.x * z.k, z.n0 - lp.y * z.k]
            walk = [[z.e0 + p.x * z.k, z.n0 - p.y * z.k] for p in pts]
            break
    meta = {
        "id": z.id, "name": z.name, "style": "resort", "size": [z.w, z.h], "deck_y": GROUND_Y,
        "pier_y": DECK_Y, "k": z.k, "origin_global": [z.e0, z.n0], "depth_n": N, "landmarks": [],
        "ad_slots": [], "palms": palms, "props": props, "paths": {}, "boats": [b for b in boat_points(land, rect)
                                                     if not over.buffer(8).contains(Point(b[0], b[2]))][:14],
        "stats": {"buildings_land": len(land_blds), "villas_overwater": len(villas),
                  "jetties": len(jetty_lines), "jetty_km": round(sum(l.difference(land).length for l in jetty_lines) / 1000, 2),
                  "deck_m2": round(walk_deck.area), "island_m2": round(land.area), "palms": len(palms),
                  "ladders": len(ladders), "spurs": len(spurs), "meshes": stats},
        "test_walk": walk, "landing": landing,
    }
    (out_dir / "meta.json").write_text(json.dumps(meta, ensure_ascii=False))
    print(z.id, json.dumps(meta["stats"]))


if __name__ == "__main__":
    main()
