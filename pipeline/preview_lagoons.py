#!/usr/bin/env python3
"""Vista de control de profundidades (0-80 m) del atolón Malé Norte/Sur desde las teselas L8."""
import sys

import numpy as np
from PIL import Image

from vm_common import DETAIL_SAMPLES, TILES_OUT, lonlat_to_global, read_tile, tile_origin, tile_size


def main(out="/workspace/screens/lagunas_male_profundidad.png", bbox=(73.2, 4.75, 73.75, 3.85)):
    i0, j0, ni, nj = 176, 120, 8, 12
    n = DETAIL_SAMPLES
    H = np.zeros((nj * (n - 1) + 1, ni * (n - 1) + 1), np.float32)
    for j in range(nj):
        for i in range(ni):
            t = read_tile(TILES_OUT / f"L8/{i0 + i}_{j0 + j}.vmt")
            h = t[0] if isinstance(t, tuple) else t["heights"]
            H[j * (n - 1):j * (n - 1) + n, i * (n - 1):i * (n - 1) + n] = np.asarray(h).reshape(n, n)
    oe, on = tile_origin(8, i0, j0)
    step = tile_size(8) / (n - 1)

    def rc(lon, lat):
        e, nn = lonlat_to_global(lon, lat)
        return int((on - nn) / step), int((e - oe) / step)

    r0, c0 = rc(bbox[0], bbox[1])
    r1, c1 = rc(bbox[2], bbox[3])
    crop = H[r0:r1, c0:c1]
    t = np.clip(np.clip(-crop, 0, None) / 80.0, 0, 1)
    cols = np.array([[200, 255, 240], [60, 210, 210], [20, 110, 190], [8, 40, 110]], np.float32)
    x = t * 3
    k = np.clip(x.astype(int), 0, 2)
    f = (x - k)[..., None]
    rgb = cols[k] * (1 - f) + cols[k + 1] * f
    rgb[crop > 0] = [60, 150, 60]
    Image.fromarray(rgb.astype(np.uint8)).resize(((c1 - c0) * 4, (r1 - r0) * 4), Image.NEAREST).save(out)
    print(out)


if __name__ == "__main__":
    main(*sys.argv[1:2])
