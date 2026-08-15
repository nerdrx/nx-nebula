/*
    SPDX-FileCopyrightText: 2026 nerdrx

    SPDX-License-Identifier: GPL-3.0-or-later

    The "blur" backdrop: a darkened, desaturated, heavily blurred copy of the
    current picture filling the bars a fitted photo leaves behind.

    Separate file for the same reason as GlassSurface.qml — a missing
    QtQuick.Effects must fail here and nowhere else. GalleryLayer always paints
    a cheap 64px-decode upscale underneath, so if this never loads the backdrop
    is merely softer rather than absent.

    The whole pipeline runs at a sixth of screen resolution and is scaled up,
    which is both cheaper and blurrier than doing it at full size. It only
    re-renders when the picture changes; nothing here touches a frame.
*/

import QtQuick
import QtQuick.Effects

Item {
    id: backdrop

    property url imageSource

    readonly property real factor: 6

    Image {
        id: small
        width: Math.max(1, backdrop.width / backdrop.factor)
        height: Math.max(1, backdrop.height / backdrop.factor)
        source: backdrop.imageSource
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 480
        asynchronous: true
        cache: false
        smooth: true
        clip: true
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        source: small
        width: small.width
        height: small.height
        transformOrigin: Item.TopLeft
        scale: backdrop.factor
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        blurMultiplier: 1.0
        // Edges stay darker than the centre, and the backdrop must never
        // compete with the photo in front of it.
        brightness: -0.52
        saturation: -0.34
    }
}
