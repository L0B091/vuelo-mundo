"""Comprueba que los props de fachada (balcones, aires) estén a <= 0.3 m de una pared real."""
import json, sys
from shapely.geometry import Point, Polygon
from shapely.strtree import STRtree

bad = 0
for zid in ("mv_male_oeste", "mv_male_este"):
    fp = json.load(open(f"data/sites/{zid}/footprints.json"))
    m = json.load(open(f"data/sites/{zid}/meta.json"))
    rings = [Polygon(p[:-1]).exterior for p in fp]
    tree = STRtree(rings)
    for kind in ("balcony", "ac"):
        far = [it for it in m["props"].get(kind, [])
               if rings[tree.nearest(Point(it[0], it[2]))].distance(Point(it[0], it[2])) > 0.3
               or it[1] < m["deck_y"] + 2.5]
        print(zid, kind, len(m["props"].get(kind, [])), "lejos:", len(far), far[:2])
        bad += len(far)
sys.exit(1 if bad else 0)
