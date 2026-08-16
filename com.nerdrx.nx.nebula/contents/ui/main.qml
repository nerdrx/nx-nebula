/*
    SPDX-FileCopyrightText: 2026 nerdrx

    SPDX-License-Identifier: GPL-3.0-or-later

    NX Nebula (Live) — three stacked layers:

        NebulaLayer    the living background, DESIGN §3
        GalleryLayer   optional photographs, shaped to fit the screen
        ClockOverlay   optional day / date / time

    All motion is gated on one boolean. `live` is false when the wallpaper is
    off screen, when its window is hidden, when the user turned animation off,
    or when Plasma's animation speed is set to instant — which is how KDE
    expresses "prefers reduced motion", and DESIGN §6 calls honouring it
    non-negotiable. Every animation is paused rather than stopped, so nothing
    jumps when it comes back and no timer ticks while it is away.
*/

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import Qt.labs.folderlistmodel

WallpaperItem {
    id: root

    readonly property bool galleryMode: root.configuration.Mode === 1
        && String(root.configuration.GalleryFolder).length > 0

    readonly property bool reducedMotion: Kirigami.Units.longDuration <= 1

    readonly property bool onScreen: root.visible && root.width > 0 && root.height > 0
        && (root.Window.window === null || root.Window.window.visible)

    readonly property bool live: root.onScreen && !root.reducedMotion

    Component.onCompleted: {
        // Hold ksplash until there is something to look at.
        root.loading = true;
    }

    /*
        The entrance: once per load, the wall says hello — nebula fades up,
        the photo row rises into place, the clock's letters track in from
        wide. Skipped wholesale under reduced motion or when switched off.
    */
    readonly property bool wantsIntro: root.configuration.Entrance && !root.reducedMotion

    onOnScreenChanged: {
        if (root.onScreen && root.wantsIntro && !introDone.value) {
            introDone.value = true;
            intro.start();
        }
    }

    QtObject { id: introDone; property bool value: false }

    SequentialAnimation {
        id: intro
        ParallelAnimation {
            NumberAnimation { target: nebula; property: "opacity"; from: 0; to: 1; duration: 1500; easing.type: Easing.OutQuad }
            SequentialAnimation {
                PauseAnimation { duration: 350 }
                ParallelAnimation {
                    NumberAnimation { target: gallery; property: "opacity"; from: 0; to: 1; duration: 1100; easing.type: Easing.OutCubic }
                    NumberAnimation { target: gallery; property: "introY"; from: 26; to: 0; duration: 1300; easing.type: Easing.OutCubic }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 650 }
                ParallelAnimation {
                    NumberAnimation { target: clock; property: "opacity"; from: 0; to: 1; duration: 1200; easing.type: Easing.OutQuad }
                    NumberAnimation { target: clock; property: "trackIn"; from: 1.8; to: 1; duration: 1600; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    /*
        The pointer, if plasmashell shares it. No buttons are accepted, so
        desktop clicks pass straight through; if hover never arrives, every
        pointer effect simply rests at centre. Heavily smoothed — nothing
        here should ever feel like it is chasing the mouse.
    */
    property real px: 0.5
    property real py: 0.5

    Behavior on px { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
    Behavior on py { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    /*
        plasmashell never delivers hover to the wallpaper layer, so the
        position comes from the nx-cursor bridge: a KWin script (the one
        Wayland party that knows the cursor) pushes coordinates to a tiny
        DBus helper that mirrors them into a runtime file, and this polls
        that at 5 Hz — far below the 1.1s smoothing above it. Global
        coordinates, mapped into this screen via the window position.
    */
    /*
        Self-bootstrap: if pointer effects are wanted but the bridge file
        never freshens, enable the KWin script, poke KWin, and start the
        helper as a transient user unit. Files-only installs (NX Hub's
        manifest engine, or plain install.sh) thus need no post-install
        hooks — the wallpaper finishes its own plumbing, once per session
        at most, and only after the user opted into pointer effects.
    */
    property bool bridgeSeen: false
    property bool bridgeKicked: false

    Timer {
        running: root.pointerWanted && !root.bridgeSeen && !root.bridgeKicked
        interval: 4000
        onTriggered: {
            root.bridgeKicked = true;
            bootstrap.connectSource(
                "kwriteconfig6 --file kwinrc --group Plugins --key nx-cursorEnabled true; "
                + "qdbus6 org.kde.KWin /KWin reconfigure; "
                + "systemctl --user restart nx-cursor.service 2>/dev/null || "
                + "systemd-run --user --unit=nx-cursor --collect \"$HOME/.local/bin/nx-cursor-helper.py\"");
        }
    }

    P5Support.DataSource {
        id: bootstrap
        engine: "executable"
    }

    readonly property bool pointerWanted: root.live && (root.configuration.PointerParallax
        || root.configuration.PointerGlow || root.configuration.PointerTile)

    // One spawn ever: where is the runtime dir?
    P5Support.DataSource {
        id: runtimeDir
        engine: "executable"
        connectedSources: root.pointerWanted ? ["echo \"${XDG_RUNTIME_DIR:-/tmp}\""] : []
        property string dir: ""
        onNewData: (source, data) => {
            runtimeDir.dir = String(data.stdout || "").trim();
            runtimeDir.disconnectSource(source);
        }
    }

    /*
        The push path: the helper renames one file inside nx-cursor.d so
        that the file NAME carries the position. This folder model hears
        the rename through inotify the moment it happens — no polling, no
        process spawns, no reads. The 120ms Behavior above interpolates
        between pushes at the display's own frame rate.
    */
    FolderListModel {
        id: cursorWatch
        folder: root.pointerWanted && runtimeDir.dir.length > 0
            ? "file://" + runtimeDir.dir + "/nx-cursor.d" : ""
        nameFilters: ["p*"]
        showDirs: false
        onCountChanged: root.readCursor()
        onFolderChanged: root.readCursor()
    }

    // A rename keeps the count at 1: the model reports it as dataChanged
    // (measured: 40 renames = 1 countChanged, 39 dataChanged). Listen to
    // every way the model can move, or the pointer goes deaf after the
    // first position.
    Connections {
        target: cursorWatch
        function onDataChanged() { root.readCursor(); }
        function onRowsInserted() { root.readCursor(); }
        function onRowsRemoved() { root.readCursor(); }
        function onModelReset() { root.readCursor(); }
    }

    property bool healed: false

    // This screen's rectangle in the virtual desktop — the correct frame
    // for global cursor coordinates. Window positions lie on Wayland;
    // Screen.virtualX/Y do not.
    readonly property real screenX: Screen.virtualX
    readonly property real screenY: Screen.virtualY

    function readCursor(): void {
        let pos = "";
        let stale = false;
        for (let i = 0; i < cursorWatch.count; ++i) {
            const n = String(cursorWatch.get(i, "fileName"));
            if (n.indexOf("p2_") === 0) {
                pos = n;
            } else if (n.indexOf("p_") === 0) {
                stale = true;   // an older helper generation is running
            }
        }
        // Hub updates swap the file on disk but not the running process;
        // a stale-prefix rename is the running process telling on itself.
        // Restart it once — files-only self-healing, no hooks required.
        if (stale && pos.length === 0 && !root.healed) {
            root.healed = true;
            bootstrap.connectSource("systemctl --user restart nx-cursor.service");
        }
        const parts = pos.split("_");
        if (parts.length !== 3) {
            return;
        }
        root.bridgeSeen = true;
        root.px = Math.max(0, Math.min(1, (Number(parts[1]) - root.screenX) / Math.max(1, Screen.width)));
        root.py = Math.max(0, Math.min(1, (Number(parts[2]) - root.screenY) / Math.max(1, Screen.height)));
    }

    NebulaLayer {
        id: nebula
        anchors.fill: parent
        // No point rasterising six full-screen layers under an opaque photo.
        visible: !(root.galleryMode && gallery.covered)
        animating: root.live && nebula.visible && root.configuration.Animate
        speed: Math.max(0.25, Math.min(3.0, root.configuration.Speed / 100))
        twinkle: root.configuration.Twinkle
        meteors: root.configuration.Meteors
        dayNight: root.configuration.DayNight
        aurora: root.configuration.Aurora
        celestials: root.configuration.Celestials
        southern: root.configuration.Southern
        realSky: root.configuration.RealSky
        clarity: weather.clarity
        pointerX: root.px
        pointerY: root.py
        parallax: root.live && root.configuration.PointerParallax
        kp: weather.kp
        lightning: weather.flash

        onReadyChanged: {
            if (nebula.ready) {
                root.loading = false;
                // The intro belongs to the moment there is something to see.
                if (root.wantsIntro && !introDone.value) {
                    introDone.value = true;
                    intro.start();
                }
            }
        }
    }

    // The sky noticing you: a soft violet glow that arrives a second late
    // wherever the pointer rests.
    Image {
        source: "../images/star-bright.png"
        readonly property real span: Math.sqrt(root.width * root.height) * 0.45
        width: span
        height: span
        x: root.px * root.width - span / 2
        y: root.py * root.height - span / 2
        opacity: root.live && root.configuration.PointerGlow ? 0.05 : 0
        smooth: true
        asynchronous: true
        visible: opacity > 0.004
    }

    WeatherLayer {
        id: weather
        anchors.fill: parent
        // The weather sits over the sky and under the photographs, exactly
        // where an atmosphere goes. Opt-in twice over: the switch, and
        // coordinates the user typed themselves.
        enabled: root.configuration.Weather
            && String(root.configuration.WeatherLat).length > 0
            && String(root.configuration.WeatherLon).length > 0
        spaceWeather: root.configuration.SpaceWeather
        latitude: Number(root.configuration.WeatherLat)
        longitude: Number(root.configuration.WeatherLon)
        live: root.live && !(root.galleryMode && gallery.covered)
    }

    GalleryLayer {
        id: gallery
        anchors.fill: parent
        property real introY: 0
        transform: Translate { y: gallery.introY }
        visible: root.galleryMode
        live: root.live && gallery.visible

        folder: root.configuration.GalleryFolder
        recursive: root.configuration.Recursive
        daily: root.configuration.DailyPhoto
        captions: root.configuration.ShowCaptions
        fitMode: root.configuration.FitMode
        backdrop: root.configuration.Backdrop
        frameStyle: root.configuration.FrameStyle
        ultrawide: root.configuration.UltrawideGallery
        interval: Math.max(5, root.configuration.Interval)
        shuffle: root.configuration.Shuffle
        burnInGuard: root.configuration.BurnInGuard
        snowCover: weather.snowDepth
        sweepOn: root.configuration.GlassSweep
        bloomBreathe: root.configuration.BloomBreathe
        pointerX: root.px
        pointerY: root.py
        parallax: root.live && root.configuration.PointerParallax
        tileAttention: root.live && root.configuration.PointerTile
        glitchSlices: root.configuration.Glitch && root.configuration.GlitchSlices
        glitchArrival: root.configuration.Glitch && root.configuration.GlitchTransition
    }

    /*
        Signal loss: every half hour or so the wall drops carrier for half a
        second — static flashes up, every photo tile tears at once — and
        then everything is exactly as it was. Master-gated like the rest of
        the glitch kit, and never under reduced motion.
    */
    Image {
        id: static_
        anchors.fill: parent
        source: "../images/grain.png"
        fillMode: Image.Tile
        smooth: false
        opacity: 0
        visible: opacity > 0.01
    }

    SequentialAnimation {
        id: signalLoss
        NumberAnimation { target: static_; property: "opacity"; from: 0; to: 0.45; duration: 40 }
        PauseAnimation { duration: 120 }
        NumberAnimation { target: static_; property: "opacity"; to: 0.1; duration: 40 }
        PauseAnimation { duration: 80 }
        NumberAnimation { target: static_; property: "opacity"; to: 0.35; duration: 40 }
        PauseAnimation { duration: 100 }
        NumberAnimation { target: static_; property: "opacity"; to: 0; duration: 60 }
    }

    Timer {
        running: root.live && root.configuration.Glitch && root.configuration.GlitchSignal
        repeat: true
        interval: 1200000 + Math.round(Math.random() * 1800000)
        onTriggered: {
            signalLoss.restart();
            gallery.glitchAll();
            clock.glitchPulse();
            interval = 1200000 + Math.round(Math.random() * 1800000);
        }
    }

    ClockOverlay {
        id: clock
        anchors.fill: parent
        visible: root.configuration.ShowClock
        active: clock.visible && root.onScreen
        position: root.configuration.ClockPosition
        timeFormat: root.configuration.TimeFormat
        almanac: root.configuration.Almanac ? nebula.almanacText : ""
        overPhotos: root.galleryMode
        // The burn-in wander is motion, so it obeys `live` (and with it
        // reduced motion), unlike the clock's once-a-minute text tick.
        drift: root.live && root.configuration.BurnInGuard
        manners: root.configuration.ClockFx
        glitchOn: root.configuration.Glitch && root.configuration.GlitchClock
    }
}
