#!/usr/bin/env python3
"""The NX Nebula cursor bridge helper.

Receives cursor positions from the KWin script over DBus
(com.nerdrx.nxcursor) and hands them to the wallpaper two ways:

a WebSocket broadcast on ws://127.0.0.1:38470. Uniform per-event
delivery at whatever rate KWin pushes; QML's WebSocket client receives
each frame the moment it is sent. No filesystem involved — earlier
generations used renames in the runtime dir as a transport, which this
version only sweeps away.

The WebSocket server is intentionally minimal (stdlib only, send-only
frames, loopback only): a handshake and unmasked text frames are all a
broadcaster needs.
"""
import base64
import hashlib
import os
import socket
import threading

from gi.repository import Gio, GLib

base = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "nx-cursor.d")
os.makedirs(base, exist_ok=True)
# Sweep earlier generations' transport files; this generation writes none.
for old in os.listdir(base):
    if old.startswith(("p_", "v_", "p2_")):
        try:
            os.remove(os.path.join(base, old))
        except OSError:
            pass

XML = ("<node><interface name='com.nerdrx.nxcursor'>"
       "<method name='set'><arg type='i' name='x' direction='in'/>"
       "<arg type='i' name='y' direction='in'/></method>"
       "</interface></node>")

MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
clients = []
clients_lock = threading.Lock()


def ws_server():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 38470))
    srv.listen(4)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=ws_handshake, args=(conn,), daemon=True).start()


def ws_handshake(conn):
    try:
        conn.settimeout(5)
        req = b""
        while b"\r\n\r\n" not in req:
            chunk = conn.recv(1024)
            if not chunk:
                conn.close()
                return
            req += chunk
        key = ""
        for line in req.decode("latin1").split("\r\n"):
            if line.lower().startswith("sec-websocket-key:"):
                key = line.split(":", 1)[1].strip()
        accept = base64.b64encode(
            hashlib.sha1((key + MAGIC).encode()).digest()).decode()
        conn.sendall((
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n").encode())
        conn.settimeout(None)
        with clients_lock:
            clients.append(conn)
    except OSError:
        conn.close()


def ws_broadcast(text):
    payload = text.encode()
    frame = bytes([0x81, len(payload)]) + payload
    with clients_lock:
        for c in clients[:]:
            try:
                c.sendall(frame)
            except OSError:
                clients.remove(c)
                try:
                    c.close()
                except OSError:
                    pass


def on_call(conn, sender, opath, iface, method, params, invocation):
    if method == "set":
        x, y = params.unpack()
        ws_broadcast(f"{x} {y}")
        invocation.return_value(None)


def on_bus(conn, name):
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    conn.register_object("/", node.interfaces[0], on_call)


threading.Thread(target=ws_server, daemon=True).start()
Gio.bus_own_name(Gio.BusType.SESSION, "com.nerdrx.nxcursor",
                 Gio.BusNameOwnerFlags.NONE, on_bus, None, None)
GLib.MainLoop().run()
