"""Constantes y utilidades compartidas del pipeline de datos de Vuelo Mundo.

Sistema global único (igual que en Godot, ver scripts/core/geo.gd):
  - Proyección: Mercator esférico EPSG:3857 (R = 6 378 137 m), norte siempre arriba.
  - Coordenada global = (este, norte) en metros de esa proyección.
  - Teselas en cuadrícula fija: nivel L -> 2^L x 2^L teselas de tamaño S_L = 2*pi*R / 2^L.
    Índice i crece hacia el este desde -pi*R, índice j crece hacia el sur desde +pi*R.
    El origen de cada tesela es su esquina NO (noroeste).
"""
import math
import os
import struct
import zlib
from pathlib import Path

R = 6378137.0
HALF = math.pi * R          # 20037508.34 m
WORLD = 2.0 * HALF

REPO = Path(__file__).resolve().parent.parent
RAW = Path(os.environ.get("VM_RAW", REPO.parent / "vuelo-mundo-data" / "raw"))
WORK = Path(os.environ.get("VM_WORK", REPO.parent / "vuelo-mundo-data" / "work"))
TILES_OUT = REPO / "data" / "tiles"

# Nivel planetario tosco y nivel de detalle regional.
COARSE_LEVEL = 6      # 64x64 teselas de ~626 km
COARSE_SAMPLES = 65   # 64 intervalos -> ~9.8 km entre muestras en el ecuador
DETAIL_LEVEL = 8      # 256x256 teselas de ~156 km
DETAIL_SAMPLES = 257  # 256 intervalos -> ~611 m entre muestras

MAGIC = b"VMT1"
HEADER = struct.Struct("<4sHBBiiHHffII")  # 36 bytes


def tile_size(level: int) -> float:
    return WORLD / (1 << level)


def tile_origin(level: int, i: int, j: int):
    """Esquina NO de la tesela en coordenadas globales (este, norte)."""
    s = tile_size(level)
    return -HALF + i * s, HALF - j * s


def lonlat_to_global(lon: float, lat: float):
    e = R * math.radians(lon)
    n = R * math.log(math.tan(math.pi / 4 + math.radians(lat) / 2))
    return e, n


def global_to_lonlat(e: float, n: float):
    lon = math.degrees(e / R)
    lat = math.degrees(2 * math.atan(math.exp(n / R)) - math.pi / 2)
    return lon, lat


def tile_of(level: int, e: float, n: float):
    s = tile_size(level)
    return int(math.floor((e + HALF) / s)), int(math.floor((HALF - n) / s))


def write_tile(path: Path, level: int, i: int, j: int, heights, mask):
    """heights: int16 (n x n, fila 0 = norte); mask: uint8 (1 = tierra)."""
    import numpy as np
    n = heights.shape[0]
    assert heights.shape == (n, n) and mask.shape == (n, n)
    raw = heights.astype("<i2").tobytes() + mask.astype("u1").tobytes()
    comp = zlib.compress(raw, 9)
    hdr = HEADER.pack(MAGIC, 1, level, 0, i, j, n, 0,
                      float(heights.min()), float(heights.max()), len(comp), len(raw))
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        f.write(hdr)
        f.write(comp)
    return len(hdr) + len(comp)


def read_tile(path: Path):
    import numpy as np
    data = Path(path).read_bytes()
    magic, ver, level, flags, i, j, n, _, hmin, hmax, csize, rsize = HEADER.unpack_from(data)
    assert magic == MAGIC
    raw = zlib.decompress(data[HEADER.size:HEADER.size + csize])
    h = np.frombuffer(raw[: n * n * 2], dtype="<i2").reshape(n, n)
    m = np.frombuffer(raw[n * n * 2:], dtype="u1").reshape(n, n)
    return dict(level=level, i=i, j=j, n=n, heights=h, mask=m)
