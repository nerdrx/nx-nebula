// Pushes the global cursor position to the nx-cursor helper over DBus,
// throttled to ~8 Hz. KWin is the only party on Wayland that knows it.
let last = 0;
workspace.cursorPosChanged.connect(() => {
    const now = Date.now();
    if (now - last < 16) {
        return;
    }
    last = now;
    const p = workspace.cursorPos;
    callDBus("com.nerdrx.nxcursor", "/", "com.nerdrx.nxcursor", "set", p.x, p.y);
});
