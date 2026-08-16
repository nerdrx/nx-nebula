# The pointer bridge

Wayland never gives a wallpaper the cursor, so NX Nebula gets it through a
three-part bridge. This file is the map: how it works, how to fix it when it
sulks, and what is still left to build.

## Architecture

```
KWin (workspace.cursorPos, the only Wayland party that knows)
  └─ kwin/nx-cursor script      pushes x,y over DBus, 16ms throttle
       └─ nx-cursor-helper.py   owns com.nerdrx.nxcursor on the session bus
            └─ broadcasts "x y" on ws://127.0.0.1:38470 (stdlib server)
                 └─ wallpaper QtWebSockets client, per-event delivery
                      └─ 90ms ease (parallax) / raw + trail (cursor star)
```

No polling, no filesystem: positions stream over a loopback WebSocket.
If nothing arrives within 4s while pointer effects are on, the wallpaper
restarts the helper (systemctl restart, falling back to systemd-run) —
that one move covers a dead helper, a stale pre-socket generation still
holding the DBus name, and a missing unit alike. The nx-cursor.d dir is
now only swept for older generations' leftovers, never written.

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
5. **Self-heal specifically (1.14.2+):** the helper generation rides in the
   position prefix itself (`p2_<x>_<y>`), so every rename proves both the
   position and the version — no separate marker to go stale. Old-prefix
   renames with no current-prefix file trigger one service restart. If the
   helper is dead entirely, nothing flows and nothing heals; that case is
   step 1.

## Still to build

- **nx-hub `postUpdate`** (the real fix for update friction): an additive,
  optional per-app command in the registry, run by the engine after the
  manifest swap. Land in `nx-hub/src/main/install/tarball-prefix.js`
  (install() completion), a `postUpdate` field in `registry/overrides.json`
  for nx-nebula (`systemctl --user restart nx-cursor plasma-plasmashell`),
  a schema note in SPEC.md, and a test beside the engine's existing ones.
- ~~Verify the v_2 self-heal~~ — replaced in 1.14.2 by the prefix-versioned
  design described in 5; the separate marker is gone.
