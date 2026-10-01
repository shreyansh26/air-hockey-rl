#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .tools
VERSION=4.5.1-stable
BASE="https://github.com/godotengine/godot/releases/download/$VERSION"
if [ ! -x .tools/Godot.app/Contents/MacOS/Godot ]; then
  curl -fL --retry 3 "$BASE/Godot_v${VERSION}_macos.universal.zip" -o .tools/godot.zip
  unzip -qo .tools/godot.zip -d .tools
fi
TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/4.5.1.stable"
if [ ! -f "$TEMPLATES/web_release.zip" ]; then
  curl -fL --retry 3 "$BASE/Godot_v${VERSION}_export_templates.tpz" -o .tools/templates.tpz
  unzip -qo .tools/templates.tpz -d .tools
  mkdir -p "$TEMPLATES"
  cp .tools/templates/* "$TEMPLATES/"
fi
tools/godot --version
