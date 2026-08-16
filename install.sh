#!/usr/bin/env bash
# NX Nebula live wallpaper — user-local install.
#
#   ./install.sh                # desktop wallpaper (pick it in the dialog)
#   ./install.sh --lockscreen   # also make it the lock screen wallpaper
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$DATA/plasma/wallpapers"
cp -r "$HERE/com.nerdrx.nx.nebula" "$DATA/plasma/wallpapers/"
echo "Installed. Right-click the desktop -> Desktop and Wallpaper -> Wallpaper type 'NX Nebula (Live)'."

if [ "${1:-}" = "--lockscreen" ]; then
  if command -v kwriteconfig6 >/dev/null; then
    kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin com.nerdrx.nx.nebula
    echo "Lock screen wallpaper set to NX Nebula (Live). Configure it under"
    echo "System Settings -> Screen Locking -> Appearance."
  else
    echo "kwriteconfig6 not found; set the lock screen plugin by hand in"
    echo "System Settings -> Screen Locking -> Appearance."
  fi
fi
