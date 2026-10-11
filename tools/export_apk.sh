#!/usr/bin/env bash
# Exportación limpia del APK: sello de commit+hora, reimportación completa, export release
# (firma de depuración para pruebas) y verificación del sello dentro del APK.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -n "$(git status --porcelain -- scripts shaders scenes data assets materials project.godot export_presets.cfg)" ]; then
  echo "árbol con cambios sin commit: commitear antes de exportar" >&2; exit 1
fi
C=$(git rev-parse --short HEAD); T=$(date -u +%Y-%m-%dT%H:%MZ)
printf '{"commit": "%s", "time": "%s"}\n' "$C" "$T" > data/build_info.json
rm -rf .godot/imported .godot/exported
godot --headless --path . --import >/dev/null 2>&1 || true
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-$HOME/.local/share/godot/keystores/debug.keystore}
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-androiddebugkey}
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-android}
OUT=build/vuelo-mundo-$C.apk
rm -f "$OUT"
godot --headless --path . --export-release "Android arm64" "$OUT" > build/export.log 2>&1
got=$(unzip -p "$OUT" assets/data/build_info.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["commit"])')
[ "$got" = "$C" ] || { echo "sello en APK ($got) != HEAD ($C)" >&2; exit 1; }
cp "$OUT" build/vuelo-mundo-release.apk
echo "OK $OUT commit=$C time=$T size=$(stat -c %s "$OUT")"
