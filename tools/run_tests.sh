#!/usr/bin/env bash
# Pruebas: lint + unitarias (GUT) + recorrido automático headless.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
command -v gdlint >/dev/null && gdlint scripts tests tools
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd
if [[ "${1:-}" == "--full" ]]; then
  # vuelo largo desde el oeste de la región de detalle, aterrizaje, caminata A->B, despegue
  "$GODOT" --headless --path . -- --autotest --start=4.1785,66.8,1500,90
fi
