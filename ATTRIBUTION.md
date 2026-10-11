# Atribución de datos y software

Vuelo Mundo usa **solo datos abiertos**. No se usa Google Earth, Google Maps ni imágenes o
geometría de esos servicios; tampoco image-blaster ni gaussian splats.

## Datos

| Fuente | Uso | Licencia |
|---|---|---|
| **ETOPO 2022 v1** (60" y 15", superficie) — NOAA National Centers for Environmental Information. DOI: [10.25921/fd45-gt74](https://doi.org/10.25921/fd45-gt74) | Relieve terrestre y batimetría del planeta tosco (60") y de la región de Maldivas (15") | Dominio público (Gobierno de EE.UU.). Cita: *NOAA National Centers for Environmental Information. 2022: ETOPO 2022 15 Arc-Second Global Relief Model. NOAA NCEI. DOI: 10.25921/fd45-gt74.* |
| **GEBCO** (a través de ETOPO 2022, que integra GEBCO entre sus fuentes batimétricas) | Profundidad del mar | GEBCO Compilation Group; uso libre con atribución |
| **Natural Earth** 10m `land`, `minor_islands`, `coastline` | Máscara de tierra/mar del planeta tosco | Dominio público — [naturalearthdata.com](https://www.naturalearthdata.com) |
| **OpenStreetMap** micro-mapa del resort (islote Lankanfinolhu: costa, edificios, villas sobre el agua, muelles `man_made=pier`, senderos) vía Overpass | `data/sites/mv_lankanfinolhu/` (sin el nombre comercial del resort) | © Colaboradores de OpenStreetMap, [ODbL 1.0](https://opendatacommons.org/licenses/odbl/) |
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
| Wood Floor Deck | Dimitrios Savva | muelles de madera y terrazas de villas sobre el agua (resort) | https://polyhaven.com/a/wood_floor_deck |
| Thatch Roof Angled | Rob Tuytel, Dimitrios Savva | techos de paja de villas y pabellones (resort) | https://polyhaven.com/a/thatch_roof_angled |
| White Planks Clean | Rob Tuytel | paredes de madera de villas (resort) | https://polyhaven.com/a/white_planks_clean |
| Qwantani Noon (Pure Sky) | Greg Zaal, Jarod Guest | cielo de mediodía (solo cielo, sin suelo) | https://polyhaven.com/a/qwantani_noon_puresky |

Mapa en el juego: «© OpenStreetMap contributors, NOAA NCEI ETOPO 2022, Natural Earth, Allen Coral Atlas (CC BY 4.0)».

## Personaje (malla base y animaciones)

| Recurso | Autor | Licencia | Fuente | Uso |
|---|---|---|---|---|
| Universal Animation Library (versión estándar gratuita, glTF "Godot Standard": maniquí con esqueleto Rigify + 45 animaciones) | Quaternius | CC0 1.0 | https://quaternius.com/packs/universalanimationlibrary.html — copia glTF publicada en https://github.com/J-Ponzo/gltf-universal-animation-library (redistribución del archivo de itch.io, 2025-06-10) | Malla base de ambos personajes; animaciones Idle, Walk, Sprint, Jump, Jump_Land |
| Universal Base Characters — cuerpos "Superhero" masculino y femenino (glTF, texturas PBR) + Universal Animation Library en esqueleto UE | Quaternius | CC0 1.0 | https://quaternius.com/packs/universalbasecharacters.html — copia glTF publicada (CC0) en https://codeberg.org/jamesonBradfield/Quaternius_IK_Rigged_with_animations (sin pasar por el checkout de itch.io) | Cuerpos separados de los personajes; las máscaras de traje (`*_suitmask.png`, `pipeline/make_suit_masks.py`), el sombreador de traje y la capa de tela simulada son obra propia |

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


## Fondo marino (clases bentónicas)

| Dato | Fuente | Licencia | Uso |
|---|---|---|---|
| Allen Coral Atlas — clases bentónicas (Sand, Seagrass, Coral/Algae, Rubble, Rock, Microalgal Mats), capa `coral-atlas:benthic_data_verbose` | Allen Coral Atlas (2022), Arizona State University et al., WFS público https://allencoralatlas.org/geoserver/ows (no la copia de Google Earth Engine) | CC BY 4.0 | `pipeline/make_benthic.py` → `data/sites/*/benthic.png`; decide el material del lecho de cada micro-mapa (`shaders/seabed.gdshader`). Cáusticas y oleaje son procedurales, obra propia. |

## Sonido

| Recurso | Autor / fuente | Licencia | Uso |
|---|---|---|---|
| "Beach Ocean Waves" (3 tomas de olas, Alkai beach) | jasinski — https://freesound.org/people/jasinski/sounds/18363/ , vía https://opengameart.org/content/beach-ocean-waves (subido por qubodup) | CC0 1.0 | `assets/audio/olas_playa_cc0.ogg` (concatenadas y pasadas a OGG Vorbis) |
| Viento, burbujas, filtro submarino | obra propia (procedural, `AvatarFx` / `AmbientAudio`) | — | — |

## Fauna marina

Mallas y animación procedurales, obra propia (`scripts/world/creature_meshes.gd`, `shaders/creature.gdshader`); sin modelos de terceros por ahora.
Ubicaciones reales (referencias públicas de buceo/conservación): Lankan Manta Point (Lankanfinolhu, Atolón Malé Norte); Hanifaru Bay (Atolón Baa, Reserva de Biosfera UNESCO); South Ari Marine Protected Area (tiburón ballena); Banana Reef (Malé Norte). Una ubicación de tiburón ballena frente a Lankanfinolhu es **de juego, no documentada**, y está marcada así en `scripts/world/sea_life.gd`.

## Corales y anémonas (obra propia)
Modelos procedurales (`scripts/world/reef_meshes.gd`), colocados sobre la clase "Coral/Algae"
(y parte de "Rock") del mapa bentónico del Allen Coral Atlas (CC BY 4.0, ver arriba).
La ubicación de cada cabezo dentro de esas clases es aleatoria, no un relevamiento.

## ESA WorldCover 2021 v200 (10 m)
© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by
ESA WorldCover consortium. Licencia CC BY 4.0. https://esa-worldcover.org — descargado del
bucket público de AWS Open Data (esa-worldcover). Uso: dónde van palmeras en el resort
(clase "Tree cover"); no se calca geometría.

## Copernicus GLO-30 DSM
© DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS
by the European Union and ESA; all rights reserved (licencia Copernicus DEM, uso libre con
atribución). Bucket público de AWS Open Data (copernicus-dem-30m). Uso: altura del dosel para
escalar palmeras. Es un modelo de superficie: en islas de 1-2 m no sirve como terreno.

## Copernicus Sentinel-2 (referencia de color del lecho)
Contains modified Copernicus Sentinel data 2026 (escena S2B_43NCE_20260125_0_L2A, color
verdadero TCI), procesada por ESA; COG públicos de AWS Open Data (sentinel-cogs) vía el
catálogo STAC earth-search (Element 84). Uso: tinte relativo de 64x64 muy difuminado sobre el
lecho de los micro-mapas (`pipeline/make_s2_tint.py`). No se calca ninguna geometría.

## Batimetría derivada de satélite (ESTIMACIÓN)
Profundidades someras (0.3-20 m) estimadas con la razón de logaritmos azul/verde de Stumpf et
al. (2003, Limnol. Oceanogr. 48:547-556) sobre bandas B02/B03 (B08 para enmascarar tierra) de
Copernicus Sentinel-2 L2A, escena S2B_43NCE_20260125_0_L2A (contains modified Copernicus
Sentinel data 2026; COG públicos de AWS Open Data). Calibración laxa por mínimos cuadrados a
profundidades típicas por clase geomorfológica del Allen Coral Atlas (planicie 1.5 m, laguna
somera 6 m, laguna profunda 20 m): d = 47.8·r − 41.2 (`data/sdb_fit.json`). Sin sondeos de
campo: es una estimación, mezclada al 70 % con el modelo existente solo donde este da < 25 m,
y atenuada en los 250 m del borde de cada micro-mapa. Aplicada a las teselas L8 cubiertas por
la escena (431 celdas, promedio a 611 m) y a las zonas de Malé y del resort.

## Kenney asset packs (CC0 1.0)
Ready-made models by Kenney (www.kenney.nl), CC0 1.0 Public Domain, used for street detail
(vehicles, traffic lights, signs, power poles, cones, shop displays/freezers/shelves, crates,
barrels, cafe tables and stools, potted plants, roof antennas, market canvas stalls, fish):
- Car Kit — https://kenney.nl/assets/car-kit
- City Kit (Roads) — https://kenney.nl/assets/city-kit-roads
- Mini Market — https://kenney.nl/assets/mini-market
- Survival Kit — https://kenney.nl/assets/survival-kit
- Furniture Kit — https://kenney.nl/assets/furniture-kit
- Food Kit — https://kenney.nl/assets/food-kit
Files: assets/models/kenney/ (list per pack in assets/ASSETS.json).

Poly Haven models (CC0 1.0, https://polyhaven.com) added for street detail: fire_hydrant, exterior_aircon_unit, planter_box_01, plastic_crate_01, wooden_crate_01, barrel_03, utility_box_01, water_manhole_cover, trashbag, propane_tank, lifebuoy, bananas, old_tyre, rollershutter_window_01, covered_car, concrete_road_barrier, modular_street_seating (authors and URLs in assets/ASSETS.json). Simplified at build time with Godot LOD generation.

## 3dassets.dev models (CC0 1.0)
Realistic-style CC0 models from https://3dassets.dev (contributor "3dassets"; the site reports
they were made with AI assistance). Scooters (4 variants), motorbike, 2 bicycles, saloon car, taxi,
panel van, hatchback, outdoor AC unit, rooftop water tank, satellite dish, balcony, laundry line,
A-frame pavement sign, container, pedestal crane, fishing boat (used as dhoni), RIB speedboat,
promenade railing. Per-file source URLs are in assets/ASSETS.json (ids "3da/..."). Files were
dequantized with gltf-transform (KHR_mesh_quantization is not supported by Godot's importer),
simplified with Godot LOD generation, vertex-compacted, and their materials baked to vertex colours.

Additional 3dassets.dev CC0 models (found via the read-only API, https://3dassets.dev/skill.md):
sodium street light, fruit & vegetable stall, market stall with awning, fish display slab, cafe
table, cafe parasol, poolside sun lounger, stone planter, roller shutter, steel bollard, fairway
buoy, seagull on post, coastal fishing trawler, manta ray, whale shark, green sea turtle, eagle ray,
coral head, and from the "Tropical Island and Palm Trees" pack: coconut palms (tall/leaning/young),
pandanus, banana clump, frangipani, sea grape, heliconia, coconut husk, driftwood, shell scatter,
rockpool anemone, intertidal coral boulder. None carry a license.attributionText; per-file URLs
in assets/ASSETS.json.

Shop sign font: Noto Sans Thaana Bold, SIL Open Font License 1.1 (assets/fonts/OFL.txt),
https://github.com/notofonts/thaana. Sign texts are generic trade names; the Dhivehi text has not
been reviewed by a native speaker.

### 3dassets.dev (CC0 1.0), additional props
- Ice cream kiosk, ice cream cart, ferry terminal kiosk, food court counter, queue barrier: https://3dassets.dev (CC0 1.0). Sources listed in assets/ASSETS.json.
- Static crowd poses are baked from Quaternius Universal Animation Library mannequin (CC0).

### Modelos generados con Meshy (text-to-3D)
- `assets/models/meshy/*.glb`: hombre, mujer, turista, pescador, niño, niña, hombre sentado, gato, perro, pelota de playa, juguetes de arena, camioneta de comida, dhoni. Generados con la API de Meshy (https://www.meshy.ai, modelo meshy-t2 + textura), cuenta paga del usuario. Licencia: según los Términos de Servicio de Meshy, los resultados de un plan pago pertenecen al titular de la cuenta (los del plan gratuito serían CC BY 4.0 con atribución a Meshy). Esto se dedujo de que la cuenta tiene créditos de suscripción mensual; conviene confirmarlo en la página de suscripción. Prompts e ids de tarea: `pipeline/meshy_tasks.json`. Costo: 195 créditos.
- `assets/characters/meshy_hero/hero.glb`: protagonista masculino (hombre joven de traje, diseño original), Meshy text-to-3D meshy-7.1 + textura PBR 2K + auto-rig de Meshy (35 créditos). Misma licencia que los demás modelos Meshy (ver arriba). Se importa con retargeting al SkeletonProfileHumanoid de Godot (`hero_bonemap.tres`); las animaciones son las del Universal Animation Library (Quaternius, CC0) reimportadas con el mismo perfil (`UAL1_humanoid.glb`). Tareas: `pipeline/meshy_hero_tasks.json`.
