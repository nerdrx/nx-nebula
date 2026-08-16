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

if [ "${1:-}" = "--pointer" ] || [ "${2:-}" = "--pointer" ]; then
  # The cursor bridge: the KWin script (the one Wayland party that sees the
  # cursor) feeds the DBus helper, which mirrors into a runtime file the
  # wallpaper polls. See helper/nx-cursor-helper.py.
  kpackagetool6 --type KWin/Script -i "$HERE/kwin/nx-cursor" 2>/dev/null \
    || kpackagetool6 --type KWin/Script -u "$HERE/kwin/nx-cursor"
  kwriteconfig6 --file kwinrc --group Plugins --key nx-cursorEnabled true
  mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
  cp "$HERE/helper/nx-cursor-helper.py" "$HOME/.local/bin/"
  cp "$HERE/helper/nx-cursor.service" "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload
  systemctl --user enable --now nx-cursor.service
  qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
  echo "Pointer bridge installed: KWin script enabled, helper service running."
fi

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
