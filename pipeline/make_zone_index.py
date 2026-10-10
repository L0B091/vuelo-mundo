#!/usr/bin/env python3
"""Genera data/zone_index.json: id, origen (esquina NO, m globales EPSG:3857), tamaño,
vecinos y punto de aterrizaje. Las zonas se definen acá en lon/lat legibles.

Los micro-mapas "mv_test_*" son BANCOS DE PRUEBA de aterrizaje/caminata/cruce de borde, no
recreaciones de Malé: se reemplazan por los micro-mapas reales en el próximo hito.
"""
import json
import math

from vm_common import REPO, R, lonlat_to_global


def k_at(n):
    return math.cosh(n / R)


zones = []

# --- Países (zonas grandes). Solo Maldivas está disponible en este hito.
def country(id_, name, lon0, lat0, lon1, lat1, neighbors, available, landing=None):
    e0, n_top = lonlat_to_global(lon0, lat1)
    e1, n_bot = lonlat_to_global(lon1, lat0)
    z = {"id": id_, "name": name, "kind": "country", "origin": [e0, n_top],
         "size": [e1 - e0, n_top - n_bot], "neighbors": neighbors, "available": available,
         "bbox_lonlat": [lon0, lat0, lon1, lat1]}
    if landing:
        le, ln = lonlat_to_global(landing[0], landing[1])
        z["landing"] = [le, ln, landing[2]]
    zones.append(z)
    return z


mv = country("MV", "Maldivas", 72.5, -0.8, 74.0, 7.2, ["IN", "LK"], True,
             landing=(73.5290, 4.1918, 2.0))  # aeropuerto Velana (Hulhulé)
country("IN", "India (pendiente)", 68.0, 6.5, 97.5, 35.5, ["MV", "LK"], False)
country("LK", "Sri Lanka (pendiente)", 79.5, 5.8, 82.0, 9.9, ["MV", "IN"], False)

# --- Micro-mapa REAL de Malé (pipeline/make_male.py + tools/gen_male.gd): la isla entera,
# partida en dos zonas oeste/este con borde común exacto. Escena en metros reales, escala k.
male = json.loads((REPO / "data" / "sites" / "male_zones.json").read_text())
walk = json.loads((REPO / "data" / "sites" / "male_test_walk.json").read_text())
ids = [z["id"] for z in male]
for z in male:
    k = z["k"]
    e, n = z["origin"]
    w, h = z["size_local"][0] * k, z["size_local"][1] * k
    entry = {"id": z["id"], "name": z["name"], "kind": "site", "parent": "MV",
             "origin": [e, n], "size": [w, h], "neighbors": [i for i in ids if i != z["id"]],
             "scene": f"res://scenes/zones/{z['id']}.scn", "available": True, "local_scale": k,
             "source": "OpenStreetMap (ODbL) + generación procedural"}
    if z["id"] == "mv_male_oeste":
        p0 = walk["points"][0]
        entry["landing"] = [p0[0], p0[1], 1.8 * k]
        entry["test_walk"] = walk["points"]
    else:
        entry["landing"] = [e + w * 0.3, n - h * 0.6, 1.8 * k]
    zones.append(entry)

# --- Resort real sobre el agua (pipeline/make_resort.py): isla Lankanfinolhu, Atolón Malé Norte.
# Se nombra por la isla (sin marca comercial). Se llega volando desde Malé (~13 km al NE).
rm = json.loads((REPO / "data" / "sites" / "mv_lankanfinolhu" / "meta.json").read_text())
k = rm["k"]
e, n = rm["origin_global"]
w, h = rm["size"][0] * k, rm["size"][1] * k
zones.append({"id": rm["id"], "name": rm["name"], "kind": "site", "parent": "MV", "origin": [e, n],
              "size": [w, h], "neighbors": ["mv_male_este"], "available": True, "local_scale": k,
              "scene": f"res://scenes/zones/{rm['id']}.scn",
              "landing": [rm["landing"][0], rm["landing"][1], rm["pier_y"] * k],
              "test_walk": rm["test_walk"],
              "source": "OpenStreetMap (ODbL) + generación procedural"})

for zz in zones:
    if zz["id"] == "mv_male_este":
        zz["neighbors"].append(rm["id"])

out = {"version": 1,
       "crs": "EPSG:3857 metros; origen = esquina NO; tamaño = (este, sur)",
       "zones": zones}
path = REPO / "data" / "zone_index.json"
path.write_text(json.dumps(out, indent=1))
print("escrito", path, "zonas:", len(zones))
