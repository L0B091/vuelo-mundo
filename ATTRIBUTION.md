# Atribución de datos y software

Vuelo Mundo usa **solo datos abiertos**. No se usa Google Earth, Google Maps ni imágenes o
geometría de esos servicios; tampoco image-blaster ni gaussian splats.

## Datos

| Fuente | Uso | Licencia |
|---|---|---|
| **ETOPO 2022 v1** (60" y 15", superficie) — NOAA National Centers for Environmental Information. DOI: [10.25921/fd45-gt74](https://doi.org/10.25921/fd45-gt74) | Relieve terrestre y batimetría del planeta tosco (60") y de la región de Maldivas (15") | Dominio público (Gobierno de EE.UU.). Cita: *NOAA National Centers for Environmental Information. 2022: ETOPO 2022 15 Arc-Second Global Relief Model. NOAA NCEI. DOI: 10.25921/fd45-gt74.* |
| **GEBCO** (a través de ETOPO 2022, que integra GEBCO entre sus fuentes batimétricas) | Profundidad del mar | GEBCO Compilation Group; uso libre con atribución |
| **Natural Earth** 10m `land`, `minor_islands`, `coastline` | Máscara de tierra/mar del planeta tosco | Dominio público — [naturalearthdata.com](https://www.naturalearthdata.com) |
| **OpenStreetMap** (`natural=coastline`, `natural=reef`) vía Overpass API | Costa e arrecifes de Maldivas en las teselas de detalle (`data/tiles/L8`) | © Colaboradores de OpenStreetMap, [ODbL 1.0](https://opendatacommons.org/licenses/odbl/). Las teselas `data/tiles/L8/*.vmt` son una base de datos derivada y se distribuyen bajo ODbL. |
| **Allen Coral Atlas** — zonas geomorfológicas (`coral-atlas:geomorphic_data_verbose`), WFS público [allencoralatlas.org/geoserver/ows](https://allencoralatlas.org/geoserver/ows) (no la copia de Google Earth Engine) | Planicies y crestas arrecifales, lagunas someras/profundas: corrección de profundidad de lagunas de atolón en `data/tiles/L8` (ver `pipeline/lagoons.py`) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). © 2018-2023 Allen Coral Atlas Partnership and Arizona State University. Cita: *Allen Coral Atlas (2022). Imagery, maps and monitoring of the world's tropical coral reefs. doi.org/10.5281/zenodo.3833242* |

### Referencias de profundidad de lagunas (valores publicados, no datos copiados)

- IUCN / UNEP, *Marine Protected Area Needs in the South Asian Seas Region, Vol. 3: Maldives* — lagunas de atolones del norte 50-60 m, del sur 80-100 m; lagunas arenosas de faros ~15 m. https://portals.iucn.org/library/sites/library/files/documents/MRN-007_3.pdf
- FAO, actas de taller sobre arrecifes de Maldivas (lagunas de 30-80 m): https://www.fao.org/4/ag124e/ag124e09.htm
- Purdy, E.G. & Bertram, G.T. (1993). *Carbonate concepts from the Maldives, Indian Ocean.* AAPG Studies in Geology 34.
- Naseer, A. & Hatcher, B.G. (2004). Inventory of the Maldives' coral reefs using morphometrics generated from Landsat ETM+ imagery. *Coral Reefs* 23: 161-168.

## Recursos gráficos (texturas PBR, cielo HDRI)

Todos de [Poly Haven](https://polyhaven.com), licencia **CC0 1.0** (dominio público; se acredita igual).
Lista mantenida en `assets/ASSETS.json` (la escribe `pipeline/fetch_assets.py`).

| Recurso | Autor(es) | Uso | Fuente |
|---|---|---|---|
| Asphalt 02 | Rob Tuytel | calles (asfalto) | https://polyhaven.com/a/asphalt_02 |
| Concrete Pavers | Amal Kumar | veredas | https://polyhaven.com/a/concrete_pavers |
| White Stucco | Amal Kumar | fachadas revocadas (se tiñen por edificio) | https://polyhaven.com/a/white_stucco |
| Concrete Floor 02 | Rob Tuytel | terrazas / azoteas, explanadas | https://polyhaven.com/a/concrete_floor_02 |
| Coral Stone Wall | Dimitrios Savva | muros de piedra de coral (mezquita antigua, muros bajos) | https://polyhaven.com/a/coral_stone_wall |
| Coast Sand 01 | Rob Tuytel | playa artificial y arena | https://polyhaven.com/a/coast_sand_01 |
| Sparse Grass | Amal Kumar | canteros y plazas verdes | https://polyhaven.com/a/sparse_grass |
| Patterned Paving | Charlotte Baglioni | Plaza de la República | https://polyhaven.com/a/patterned_paving |
| Corrugated Iron 02 | Jenelle van Heerden, Sergej Majboroda | techos de chapa | https://polyhaven.com/a/corrugated_iron_02 |
| Qwantani Noon (Pure Sky) | Greg Zaal, Jarod Guest | cielo de mediodía (solo cielo, sin suelo) | https://polyhaven.com/a/qwantani_noon_puresky |

Mapa en el juego: «© OpenStreetMap contributors, NOAA NCEI ETOPO 2022, Natural Earth, Allen Coral Atlas (CC BY 4.0)».

## Personaje (malla base y animaciones)

| Recurso | Autor | Licencia | Fuente | Uso |
|---|---|---|---|---|
| Universal Animation Library (versión estándar gratuita, glTF "Godot Standard": maniquí con esqueleto Rigify + 45 animaciones) | Quaternius | CC0 1.0 | https://quaternius.com/packs/universalanimationlibrary.html — copia glTF publicada en https://github.com/J-Ponzo/gltf-universal-animation-library (redistribución del archivo de itch.io, 2025-06-10) | Malla base de ambos personajes; animaciones Idle, Walk, Sprint, Jump, Jump_Land |

Las poses de vuelo (despegue, crucero con brazos atrás, puño adelante, flotación erguida y
aterrizaje pesado), el pelo, la capa, el cinturón, los colores y todos los efectos (onda
expansiva, polvo, marca de impacto, líneas de velocidad) son obra propia del proyecto (CC0).
Diseño original de superhéroe: no reproduce ningún personaje con derechos de autor.

## Software

| Componente | Licencia |
|---|---|
| Godot Engine 4.7 | MIT |
| GUT (Godot Unit Test) 9.7.1, en `addons/gut` | MIT (`addons/gut/LICENSE.md`) |
| GDAL, NumPy, SciPy, Shapely, pyproj, Pillow (solo pipeline) | Licencias libres (MIT/BSD/Apache) |
