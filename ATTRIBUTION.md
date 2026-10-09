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

Mapa en el juego: «© OpenStreetMap contributors, NOAA NCEI ETOPO 2022, Natural Earth».

## Software

| Componente | Licencia |
|---|---|
| Godot Engine 4.7 | MIT |
| GUT (Godot Unit Test) 9.7.1, en `addons/gut` | MIT (`addons/gut/LICENSE.md`) |
| GDAL, NumPy, SciPy, Shapely, pyproj, Pillow (solo pipeline) | Licencias libres (MIT/BSD/Apache) |
