#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/4.5.1.stable"
mkdir -p android/build
unzip -qo "$TEMPLATES/android_source.zip" -d android/build
printf '4.5.1.stable' > android/.build_version
printf 'Generated android/build; open this folder in Android Studio.\n'
