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

        onReadyChanged: {
            if (nebula.ready) {
                root.loading = false;
            }
        }
    }

    GalleryLayer {
        id: gallery
        anchors.fill: parent
        visible: root.galleryMode
        live: root.live && gallery.visible

        folder: root.configuration.GalleryFolder
        fitMode: root.configuration.FitMode
        backdrop: root.configuration.Backdrop
        frameStyle: root.configuration.FrameStyle
        ultrawide: root.configuration.UltrawideGallery
        interval: Math.max(5, root.configuration.Interval)
        shuffle: root.configuration.Shuffle
        burnInGuard: root.configuration.BurnInGuard
    }

    ClockOverlay {
        id: clock
        anchors.fill: parent
        visible: root.configuration.ShowClock
        active: clock.visible && root.onScreen
        position: root.configuration.ClockPosition
        timeFormat: root.configuration.TimeFormat
        overPhotos: root.galleryMode
        // The burn-in wander is motion, so it obeys `live` (and with it
        // reduced motion), unlike the clock's once-a-minute text tick.
        drift: root.live && root.configuration.BurnInGuard
    }
}
