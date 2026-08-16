#!/usr/bin/env python3
"""Owns com.nerdrx.nxcursor on the session bus and mirrors what the KWin
script sends into $XDG_RUNTIME_DIR/nx-cursor, which the wallpaper polls.
Writes are atomic (rename) so the reader never sees a torn line."""
import os
from gi.repository import Gio, GLib

base = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "nx-cursor.d")
os.makedirs(base, exist_ok=True)
# Sweep older generations' droppings so the watcher only ever sees
# one coherent story in this directory.
for old in os.listdir(base):
    if old.startswith(("p_", "v_")):
        try:
            os.remove(os.path.join(base, old))
        except OSError:
            pass
current = None
XML = ("<node><interface name='com.nerdrx.nxcursor'>"
       "<method name='set'><arg type='i' name='x' direction='in'/>"
       "<arg type='i' name='y' direction='in'/></method>"
       "</interface></node>")


def on_call(conn, sender, opath, iface, method, params, invocation):
    global current
    if method == "set":
        x, y = params.unpack()
        # The position IS the file name: a rename is one inotify event the
        # wallpaper's folder model hears instantly — no polling, no reads.
        # The version rides in the prefix: every rename proves both the
        # position AND which helper generation produced it, so the
        # wallpaper's staleness check can never miss an update.
        name = os.path.join(base, f"p2_{x}_{y}")
        if current is None:
            open(name, "w").close()
        else:
            try:
                os.replace(current, name)
            except OSError:
                open(name, "w").close()
        current = name
        invocation.return_value(None)


def on_bus(conn, name):
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    conn.register_object("/", node.interfaces[0], on_call)


Gio.bus_own_name(Gio.BusType.SESSION, "com.nerdrx.nxcursor",
                 Gio.BusNameOwnerFlags.NONE, on_bus, None, None)
GLib.MainLoop().run()
