#!/usr/bin/env bash
# Captura con render real (Vulkan por software en Xvfb si no hay GPU).
# Uso: tools/screenshot.sh salida.png [args del juego…]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?ruta de salida}"; shift
xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-godot}" --path . --rendering-method mobile \
  --resolution 1280x720 -- --screenshot="$OUT" "$@"
