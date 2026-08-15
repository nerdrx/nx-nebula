/*
    SPDX-FileCopyrightText: 2026 nerdrx

    SPDX-License-Identifier: GPL-3.0-or-later

    The bloom on its own: a blurred halo escaping from behind a square tile,
    with none of the rounded-glass treatment.

    Separate file for the usual reason — a missing QtQuick.Effects must fail
    here and nowhere else; GalleryCard keeps its plain plate when this never
    loads. The halo body itself is hidden behind the card, so only the glow
    that bleeds past the edges is ever seen, exactly like the bloom half of
    GlassSurface.
*/

import QtQuick
import QtQuick.Effects

Item {
    id: halo

    /** Glow colour; GalleryCard feeds it the photo's own dominant hue. */
    property color tint: "#7700ff"

    Item {
        id: shape
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            color: halo.tint
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: shape
        // Auto padding stops at the blur radius, where a gaussian is still
        // visibly non-zero — the glow ends on a hard rectangle. Triple the
        // room lets it actually reach black before the texture runs out.
        autoPaddingEnabled: false
        paddingRect: Qt.rect(120, 120, 120, 120)
        blurEnabled: true
        blur: 1.0
        blurMax: 40
        opacity: 0.34
    }
}
