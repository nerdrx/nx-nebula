# The pointer bridge

Wayland never gives a wallpaper the cursor, so NX Nebula gets it through a
three-part bridge. This file is the map: how it works, how to fix it when it
sulks, and what is still left to build.

## Architecture

```
KWin (workspace.cursorPos, the only Wayland party that knows)
  └─ kwin/nx-cursor script      pushes x,y over DBus, 16ms throttle
       └─ nx-cursor-helper.py   owns com.nerdrx.nxcursor on the session bus
            └─ renames $XDG_RUNTIME_DIR/nx-cursor.d/p_<x>_<y>
                 └─ wallpaper FolderListModel hears the rename via inotify
                      └─ 120ms OutCubic Behavior → parallax / glow / tile
```

No polling anywhere: the position travels as a file *rename*, one inotify
event, sub-5ms. The helper also stamps `v_2` in the same directory; the
wallpaper restarts the service once if positions flow without that marker
(the post-update state: new files on disk, old process running).

## Install / update, manually

```bash
cd /run/media/nerdrx/Lex/claude/nx-nebula
./install.sh --pointer        # KWin script + helper + user service, enabled
systemctl --user restart nx-cursor.service plasma-plasmashell.service
```

## When it isn't working, check in this order

1. **Is the helper alive and current?**
   `systemctl --user status nx-cursor` — if dead or older than the repo copy:
   `cp helper/nx-cursor-helper.py ~/.local/bin/ && systemctl --user restart nx-cursor`
2. **Is the directory moving?**
   `ls $XDG_RUNTIME_DIR/nx-cursor.d/` while wiggling the mouse — the `p_*`
   name must change constantly and `v_2` must exist. If the dir is missing,
   the helper never started; if `p_*` is frozen, the KWin script is off:
   `kwriteconfig6 --file kwinrc --group Plugins --key nx-cursorEnabled true`
   then `qdbus6 org.kde.KWin /KWin reconfigure`.
3. **Helper runs but no renames?** The KWin script's DBus calls are failing —
   check `journalctl --user -u nx-cursor` and KWin's log for
   `com.nerdrx.nxcursor` errors. GLib/PyGObject must be installed
   (`python-gobject` on CachyOS).
4. **Everything above moves but the wall doesn't?** plasmashell is running
   old QML — restart it. Also confirm a Pointer toggle is actually on in the
   wallpaper config; all three off disables the whole chain including the
   self-heal.
5. **Self-heal specifically:** it only fires when positions arrive *without*
   `v_2` — if the helper is dead entirely, nothing flows and nothing heals.
   That case needs the service running at least once (step 1). Suspected
   remaining bug as of 1.14.1: FolderListModel may deliver `v_2` in its
   first snapshot and never re-evaluate, so verify with the steps above and
   treat the marker logic as unproven.

## Still to build

- **nx-hub `postUpdate`** (the real fix for update friction): an additive,
  optional per-app command in the registry, run by the engine after the
  manifest swap. Land in `nx-hub/src/main/install/tarball-prefix.js`
  (install() completion), a `postUpdate` field in `registry/overrides.json`
  for nx-nebula (`systemctl --user restart nx-cursor plasma-plasmashell`),
  a schema note in SPEC.md, and a test beside the engine's existing ones.
- **Verify the v_2 self-heal live** (see 5 above) — if FolderListModel
  snapshots betray it, switch the marker check to the helper renaming the
  position file to `p2_<x>_<y>` (version folded into the prefix the watcher
  already tracks) and drop the separate marker file entirely. That variant
  cannot go stale.
