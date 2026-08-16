#!/usr/bin/env python3
"""Owns com.nerdrx.nxcursor on the session bus and mirrors what the KWin
script sends into $XDG_RUNTIME_DIR/nx-cursor, which the wallpaper polls.
Writes are atomic (rename) so the reader never sees a torn line."""
import os
from gi.repository import Gio, GLib

path = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "nx-cursor")
XML = ("<node><interface name='com.nerdrx.nxcursor'>"
       "<method name='set'><arg type='i' name='x' direction='in'/>"
       "<arg type='i' name='y' direction='in'/></method>"
       "</interface></node>")


def on_call(conn, sender, opath, iface, method, params, invocation):
    if method == "set":
        x, y = params.unpack()
        tmp = path + ".tmp"
        with open(tmp, "w") as fh:
            fh.write(f"{x} {y}\n")
        os.replace(tmp, path)
        invocation.return_value(None)


def on_bus(conn, name):
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    conn.register_object("/", node.interfaces[0], on_call)


Gio.bus_own_name(Gio.BusType.SESSION, "com.nerdrx.nxcursor",
                 Gio.BusNameOwnerFlags.NONE, on_bus, None, None)
GLib.MainLoop().run()
