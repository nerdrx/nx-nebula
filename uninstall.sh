#!/usr/bin/env bash
set -euo pipefail
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/wallpapers/com.nerdrx.nx.nebula"
echo "NX Nebula removed. Pick another wallpaper type if it was active."
