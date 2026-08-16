#!/usr/bin/env bash
# Package NX Nebula for NX Hub and publish a GitHub release.
#
# The tarball is laid out as `share/plasma/wallpapers/<pluginId>/…` so the
# hub's tarball-prefix engine (prefix ~/.local, per-file manifest) installs,
# updates, and uninstalls it exactly. Version comes from metadata.json.
#
#   scripts/release.sh              # package + publish vX.Y.Z
#   scripts/release.sh --dry-run    # package + checksum only
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PLUGIN="com.nerdrx.nx.nebula"
REPO="nerdrx/nx-nebula"
VERSION="$(python3 -c "import json;print(json.load(open('$PLUGIN/metadata.json'))['KPlugin']['Version'])")"
[ -n "$VERSION" ] || { echo "no KPlugin.Version in metadata.json"; exit 1; }

OUT="dist"
NAME="nx-nebula-${VERSION}-linux.tar.gz"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/share/plasma/wallpapers" "$STAGE/share/kwin/scripts" \
  "$STAGE/share/systemd/user" "$STAGE/bin" "$OUT"
cp -r "$PLUGIN" "$STAGE/share/plasma/wallpapers/"
# The cursor bridge rides along as plain files; the wallpaper bootstraps
# the service and the KWin script itself on first use, so the hub's
# file-manifest engine is all the install logic anyone needs.
cp -r kwin/nx-cursor "$STAGE/share/kwin/scripts/"
cp helper/nx-cursor-helper.py "$STAGE/bin/"
cp helper/nx-cursor.service "$STAGE/share/systemd/user/"
tar -czf "$OUT/$NAME" -C "$STAGE" share bin
( cd "$OUT" && sha256sum "$NAME" > "$NAME.sha256" )
echo "packaged: $OUT/$NAME ($(du -h "$OUT/$NAME" | cut -f1))"

if [ "${1:-}" = "--dry-run" ]; then
  echo "dry run — GitHub untouched"
  exit 0
fi

gh release create "v$VERSION" --repo "$REPO" \
  --title "NX Nebula $VERSION" \
  --notes "Living NX nebula wallpaper for KDE Plasma — drifting nebula, clock overlay, ultrawide-aware photo gallery. Installable and auto-updatable through [NX Hub](https://github.com/nerdrx/nx-hub); manual install via \`install.sh\`." \
  "$OUT/$NAME" "$OUT/$NAME.sha256"
echo "published v$VERSION"
