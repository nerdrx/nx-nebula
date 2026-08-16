/*
    SPDX-FileCopyrightText: 2026 nerdrx

    SPDX-License-Identifier: GPL-3.0-or-later

    The bloom on its own: a blurred halo escaping from behind a square tile,
    with none of the rounded-glass treatment.

    Separate file for the usual reason — a missing QtQuick.Effects must fail
    here and nowhere else; GalleryCard keeps its plain plate when this never
    loads.

    Geometry note, learned the hard way: MultiEffect's padding (auto or
    manual paddingRect) mis-anchors its texture when the item is resized
    after creation — and gallery cards resize whenever a freshly decoded
    photo brings its real aspect. So nothing here paints outside its bounds.
    This item is `reach` larger than the card on every side (the loader
    oversizes by exactly that), the glowing shape is inset back to the card
    rect, and the blur spreads into room the item already owns. Resizes flow
    through plain anchors and can never leave the halo misaligned.
*/

import QtQuick
import QtQuick.Effects

Item {
    id: halo

    /** Glow colour; GalleryCard feeds it the photo's own dominant hue. */
    property color tint: "#7700ff"

    /** Room the glow gets on every side. The loader that creates this item
        must oversize it by the same amount. */
    readonly property int reach: 120

    Item {
        id: shape
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: halo.reach
            color: halo.tint
        }
    }

    /** Swells the glow ±0.05 on a slow period when on. */
    property bool breathe: false
    property real swell: 0
    property real swellBoost: 0

    SequentialAnimation {
        running: true
        paused: !halo.breathe
        loops: Animation.Infinite
        NumberAnimation { target: halo; property: "swell"; from: 0; to: 0.05; duration: 4400; easing.type: Easing.InOutSine }
        NumberAnimation { target: halo; property: "swell"; from: 0.05; to: -0.04; duration: 8800; easing.type: Easing.InOutSine }
        NumberAnimation { target: halo; property: "swell"; from: -0.04; to: 0; duration: 4400; easing.type: Easing.InOutSine }
    }

    MultiEffect {
        anchors.fill: parent
        source: shape
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: 40
        opacity: 0.34 + halo.swell + halo.swellBoost
    }
}
