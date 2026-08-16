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
