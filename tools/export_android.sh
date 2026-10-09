#!/usr/bin/env bash
# Exporta el APK de depuración (arm64-v8a). Requiere plantillas de exportación 4.7.2 y el
# SDK de Android configurado en la configuración del editor (ver README).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
"${GODOT:-godot}" --headless --path . --export-debug "Android arm64" build/vuelo-mundo-debug.apk
ls -lh build/vuelo-mundo-debug.apk
