/*
    SPDX-FileCopyrightText: 2026 nerdrx

    SPDX-License-Identifier: GPL-3.0-or-later

    Rounded corners and a violet bloom for a gallery card.

    This lives in its own file on purpose. QtQuick.Effects ships with Qt 6 and
    its shaders are precompiled — nothing here needs qsb — but if a
    distribution splits it out, a missing import must fail *this* file and
    nothing else. GalleryCard loads it through a Loader and simply keeps its
    square-cornered plate when the Loader reports an error.

    Two effects rather than one, and the reason is a real MultiEffect
    constraint: `autoPaddingEnabled` grows the effect's texture but does not
    grow `maskSource` with it, so a padded effect samples its mask stretched
    and eats into the picture — badly on a narrow portrait, invisibly on a
    wide landscape. So the rounding runs unpadded (exact, no bleed) and the
    bloom, which needs to draw outside the card, is a separate padded pass
    underneath whose own body the card covers completely.

    The bloom is violet rather than black on purpose. DESIGN --shadow-lift
    pairs a dark shadow with a violet glow; over a near-black nebula the dark
    half does nothing at all, and only the glow actually lifts the card off
    the field.
*/

import QtQuick
import QtQuick.Effects

Item {
    id: glass

    /** The item to round off. Assigned by GalleryCard.onLoaded. */
    property Item plate: null
    property real cornerRadius: 18

    /** Bloom colour; GalleryCard feeds it the photo's own dominant hue. */
    property color tint: "#7700ff"

    // A solid violet card-shape, blurred outward. Everything inside the
    // card's own outline is hidden behind the picture; only the halo escapes.
    Item {
        id: bloomShape
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: glass.cornerRadius
            color: glass.tint
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: bloomShape
        autoPaddingEnabled: true
        blurEnabled: true
        blur: 1.0
        blurMax: 40
        opacity: 0.34
    }

    MultiEffect {
        anchors.fill: parent
        source: glass.plate
        // Must stay false: see the note at the top of the file.
        autoPaddingEnabled: false
        maskEnabled: true
        maskSource: maskShape
        maskThresholdMin: 0.45
        maskSpreadAtMin: 0.35
    }

    Item {
        id: maskShape
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: glass.cornerRadius
            color: "#ffffff"
        }
    }
}
