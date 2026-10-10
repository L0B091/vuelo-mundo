#!/usr/bin/env python3
"""Máscaras de traje de superhéroe para los Universal Base Characters (Quaternius, CC0).

Los cuerpos base vienen "en ropa interior" (piel + short). Para los trajes se hornea una
máscara en el espacio UV de cada cuerpo, a partir de la pose de reposo: R = traje (del cuello
a los tobillos, sin manos), G = guantes/botas (manos y pies: acento), B = banda del pecho
(emblema/franja). El sombreador del traje mezcla color/tela con la textura original.
"""
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
DIR = REPO / "assets" / "characters" / "superhero"
N = 1024


def read_accessor(g, binv, idx):
    acc = g["accessors"][idx]
    bv = g["bufferViews"][acc["bufferView"]]
    comp = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[acc["componentType"]]
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    itemsize = np.dtype(comp).itemsize * ncomp
    if stride and stride != itemsize:
        raw = np.frombuffer(binv, np.uint8, count=stride * acc["count"], offset=off).reshape(acc["count"], stride)
        return raw[:, :itemsize].copy().view(comp).reshape(acc["count"], ncomp)
    return np.frombuffer(binv, comp, count=acc["count"] * ncomp, offset=off).reshape(acc["count"], ncomp)


def bake(name):
    g = json.loads((DIR / f"{name}.gltf").read_text())
    binv = (DIR / g["buffers"][0]["uri"]).read_bytes()
    # el cuerpo es la malla con más vértices (ojos y cejas son chicas)
    mesh = max(g["meshes"], key=lambda m: sum(g["accessors"][p["attributes"]["POSITION"]]["count"]
                                              for p in m["primitives"]))
    img = np.zeros((N, N, 3), np.float32)
    for prim in mesh["primitives"]:
        P = read_accessor(g, binv, prim["attributes"]["POSITION"]).astype(np.float64)
        UV = read_accessor(g, binv, prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
        I = read_accessor(g, binv, prim["indices"]).reshape(-1, 3)
        y = P[:, 1]
        h = y.max() - y.min()
        y0 = y.min()
        yn = (y - y0) / h
        ax = np.abs(P[:, 0]) / h
        # regiones (pose A/T de reposo): manos = lejos del eje a la altura de la cadera o más
        hands = ax > 0.40  # pose T de reposo: de la muñeca hacia afuera
        feet = yn < 0.055
        neck = (yn > 0.835) & (ax < 0.10)
        suit = ~(hands | feet | neck)
        chest = (yn > 0.70) & (yn < 0.76) & (ax < 0.12) & (P[:, 2] > 0)
        val = np.stack([suit.astype(float), (hands | feet).astype(float), chest.astype(float)], 1)
        for tri in I:
            uv = UV[tri] * (N - 1)
            v = val[tri].mean(0)
            x0, x1 = int(np.floor(uv[:, 0].min())), int(np.ceil(uv[:, 0].max()))
            z0, z1 = int(np.floor(uv[:, 1].min())), int(np.ceil(uv[:, 1].max()))
            if x1 - x0 > 200 or z1 - z0 > 200:
                continue
            xs, zs = np.meshgrid(np.arange(x0, x1 + 1), np.arange(z0, z1 + 1))
            a, b, c = uv
            d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
            if abs(d) < 1e-9:
                continue
            l1 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (zs - c[1])) / d
            l2 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (zs - c[1])) / d
            l3 = 1 - l1 - l2
            m = (l1 >= -0.02) & (l2 >= -0.02) & (l3 >= -0.02)
            xx, zz = np.clip(xs[m], 0, N - 1), np.clip(zs[m], 0, N - 1)
            img[zz, xx] = np.maximum(img[zz, xx], v)
    # un poco de dilatación para que no queden costuras en los bordes UV
    from scipy.ndimage import grey_dilation
    for ch in range(3):
        img[:, :, ch] = grey_dilation(img[:, :, ch], size=(5, 5))
    Image.fromarray((img * 255).astype(np.uint8)).save(DIR / f"{name}_suitmask.png")
    print(name, "máscara", (img[:, :, 0] > 0.5).mean().round(3))


if __name__ == "__main__":
    for n in ("Superhero_Male_FullBody", "Superhero_Female_FullBody"):
        bake(n)
