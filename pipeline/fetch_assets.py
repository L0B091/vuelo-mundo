#!/usr/bin/env python3
"""Descarga materiales PBR y cielo HDRI CC0 de Poly Haven (https://polyhaven.com, CC0 1.0).

Se bajan a 1k (móvil): color (diff), normal OpenGL (nor_gl) y ORM empaquetado (arm =
AO en R, rugosidad en G, metal en B, que es justo el orden ORM que espera Godot).
Cada recurso queda registrado con URL y licencia en assets/ASSETS.json (y en ATTRIBUTION.md).
"""
import json
import os
import urllib.request

from vm_common import REPO

API = "https://api.polyhaven.com"
UA = {"User-Agent": "vuelo-mundo-pipeline/0.2"}
RES = "1k"
# id Poly Haven -> uso en el juego
TEXTURES = {
    "asphalt_02": "calles (asfalto)",
    "concrete_pavers": "veredas",
    "white_stucco": "fachadas revocadas (se tiñen por edificio)",
    "concrete_floor_02": "terrazas / azoteas, explanadas",
    "coral_stone_wall": "muros de piedra de coral (mezquita antigua, muros bajos)",
    "coast_sand_01": "playa artificial y arena",
    "sparse_grass": "canteros y plazas verdes",
    "patterned_paving": "Plaza de la República",
    "corrugated_iron_02": "techos de chapa",
}
HDRIS = {"qwantani_noon_puresky": "cielo de mediodía (solo cielo, sin suelo)"}
MAPS = {"Diffuse": "diff", "nor_gl": "nor_gl", "arm": "arm"}


def fetch_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.loads(r.read())


def download(url, path):
    if os.path.exists(path):
        return
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r:
        data = r.read()
    with open(path + ".part", "wb") as f:
        f.write(data)
    os.replace(path + ".part", path)
    print("  ", os.path.relpath(path, REPO), len(data) // 1024, "KB")


def main():
    out = REPO / "assets"
    manifest = []
    for aid, use in TEXTURES.items():
        info = fetch_json(f"{API}/info/{aid}")
        files = fetch_json(f"{API}/files/{aid}")
        d = out / "textures" / aid
        d.mkdir(parents=True, exist_ok=True)
        for key, suffix in MAPS.items():
            url = files[key][RES]["jpg"]["url"]
            download(url, str(d / f"{aid}_{suffix}.jpg"))
        manifest.append({
            "id": aid, "kind": "texture", "use": use, "name": info.get("name"),
            "authors": list(info.get("authors", {}).keys()),
            "source": f"https://polyhaven.com/a/{aid}", "license": "CC0 1.0",
        })
    for aid, use in HDRIS.items():
        info = fetch_json(f"{API}/info/{aid}")
        files = fetch_json(f"{API}/files/{aid}")
        d = out / "hdri"
        d.mkdir(parents=True, exist_ok=True)
        download(files["hdri"]["2k"]["hdr"]["url"], str(d / f"{aid}_2k.hdr"))
        manifest.append({
            "id": aid, "kind": "hdri", "use": use, "name": info.get("name"),
            "authors": list(info.get("authors", {}).keys()),
            "source": f"https://polyhaven.com/a/{aid}", "license": "CC0 1.0",
        })
    with open(out / "ASSETS.json", "w") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)
    print("listo:", len(manifest), "recursos")


if __name__ == "__main__":
    main()
