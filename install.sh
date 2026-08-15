#!/usr/bin/env bash
# NX Nebula live wallpaper — user-local install.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$DATA/plasma/wallpapers"
cp -r "$HERE/com.nerdrx.nx.nebula" "$DATA/plasma/wallpapers/"
echo "Installed. Right-click the desktop -> Desktop and Wallpaper -> Wallpaper type 'NX Nebula (Live)'."
