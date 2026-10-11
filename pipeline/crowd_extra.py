"""Gente en botes (Malé y resort) y vida de resort: huéspedes junto a las reposeras, personal en
los muelles, chicos con pelotas en la playa. Usa los modelos del registro (gente Meshy)."""
import math


def _f(a, b, c=0):
    v = math.sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453
    return v - math.floor(v)


def boats_people(meta):
    P = meta["props"]
    for b in meta.get("boats", []):
        x, _, z, yaw = b[:4]
        n = 1 + int(_f(x, z, 1) * 3)
        fx, fz = math.sin(yaw), math.cos(yaw)
        for q in range(n):
            o = (q - (n - 1) / 2) * 1.6
            kind = "m_fisher" if _f(x, z, q + 2) < 0.6 else "m_man"
            P.setdefault(kind, []).append([round(x + fx * o, 2), 0.85, round(z + fz * o, 2), yaw + q, 1.0])


def resort_people(meta):
    P = meta["props"]
    y = meta["deck_y"]
    for it in P.get("lounger", []):
        x, ly, z, yaw = it[:4]
        f = _f(x, z, 5)
        fx, fz = math.cos(yaw), -math.sin(yaw)
        if f < 0.22:
            P.setdefault("m_tourist", []).append([x + fx * 0.9, ly, z + fz * 0.9, yaw + 1.5, 1.0])
        elif f < 0.34:
            P.setdefault("m_sit", []).append([x, ly + 0.25, z, yaw, 1.0])
        elif f < 0.40:
            P.setdefault("m_girl" if f < 0.37 else "m_boy", []).append([x + fx * 2.2, ly, z + fz * 2.2, yaw, 1.0])
            P.setdefault("beach_ball", []).append([x + fx * 3.4, ly + 0.22, z + fz * 3.4, 0.0, 1.0])
        elif f < 0.43:
            P.setdefault("m_man", []).append([x - fx * 1.2, ly, z - fz * 1.2, yaw, 1.0])  # personal
    walk = meta.get("test_walk") or []
    del y
    return walk
