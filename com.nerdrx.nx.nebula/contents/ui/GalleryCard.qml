/*
    SPDX-FileCopyrightText: 2026 nerdrx

    SPDX-License-Identifier: GPL-3.0-or-later

    One photo slot: a pair of Images that cross-fade, wrapped in the NX
    tier-1 glass treatment (DESIGN §4).

    The lit edge is a rounded gradient plate sitting *behind* the picture and
    one pixel larger on every side, so the only part of it you ever see is a
    1px hairline — bright lilac at the top, through violet and a breath of
    cyan, to black at the bottom. That is `--edge-lit`, and it is why the card
    reads as a physical pane of glass rather than a bordered rectangle.

    The plate and the picture are one item, which matters: the rounded mask
    and the drop shadow are applied to the pair together, so the shadow falls
    outside the hairline instead of smearing across it.
*/

pragma ComponentBehavior: Bound

import QtCore
import QtQuick

Item {
    id: card

    /** The picture to show. Changing it starts a cross-fade. */
    property url imageSource

    /** 0 = fit (never crop), 1 = fill (crop), 2 = pan and scan. */
    property int fitMode: 0

    /** 0 = plain lit tile, 1 = tile with a glow behind it, 2 = rounded
        glass card. See `glassActive` for whether 2 actually happened. */
    property int frameStyle: 1

    /** Motion gate, shared with the rest of the wallpaper. */
    property bool live: true

    /** Corner radius, DESIGN --radius scaled to the screen. */
    property real frameRadius: 18

    /** Natural aspect of whatever is on screen. 1.5 until something loads. */
    readonly property real aspect: (front.status === Image.Ready && front.implicitHeight > 0)
        ? front.implicitWidth / front.implicitHeight
        : 1.5

    readonly property bool loaded: front.status === Image.Ready

    /** The incoming picture could not be decoded. The gallery skips it;
        without this a broken file squats in the hidden slot for a turn. */
    signal sourceFailed()

    /*
        Whether the glass treatment is actually in effect.

        Two ways it can fail, and both must fall back to the plain plate
        rather than to a blank card: QtQuick.Effects missing (Loader.Error),
        or a session running the software scene graph, where layer.enabled
        renders nothing at all and the picture would simply vanish. The
        square-tile bloom degrades the same way — the halo just never shows.
    */
    readonly property bool effectsPossible: GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool glassActive: card.frameStyle === 2 && card.effectsPossible
        && glassLoader.status === Loader.Ready

    /*
        The glow behind the card, tinted to the photograph itself.

        Sampled once per picture through an 8x8 Canvas — a one-shot at
        rotation time, never per frame. Only the hue is taken from the photo;
        saturation and lightness are pinned so the halo always glows like the
        brand bloom instead of going muddy on a dark image. A picture with no
        colour worth trusting (or any sampling failure at all) falls back to
        the NX violet.
    */
    property color glowColor: "#7700ff"

    Behavior on glowColor {
        // Ride along with the 800ms crossfade.
        ColorAnimation { duration: 800; easing.type: Easing.InOutQuad }
    }

    // Which of the two slots is currently on top.
    property bool useA: true
    readonly property Image front: useA ? imgA : imgB
    readonly property Image back: useA ? imgB : imgA

    // Bumped per picture so each one pans a different way for a different
    // length of time, and so the outgoing picture keeps its own motion while
    // the incoming one starts fresh.
    property int generation: 0

    // Decode budget. Quantised to 256px steps so nudging a panel does not
    // throw away every decoded pixmap.
    readonly property int capH: Math.min(4096, Math.ceil(Math.max(1, height) * Screen.devicePixelRatio / 256) * 256)
    readonly property int capW: Math.min(4096, Math.ceil(Math.max(1, width) * Screen.devicePixelRatio / 256) * 256)

    function promote(img: Image): void {
        card.useA = (img === imgA);
    }

    /** Which slot of the gallery row this is; only keeps the sample files
        of side-by-side cards from fighting over one name. */
    property int cardIndex: 0

    // Sampling waits out the 800ms crossfade: a grab taken mid-fade sees
    // the picture at a fraction of its opacity and reads too dark.
    onUseAChanged: sampleDelay.restart()
    onFrameStyleChanged: sampleDelay.restart()

    Timer {
        id: sampleDelay
        interval: 900
        onTriggered: card.requestGlowSample()
    }

    /*
        Getting pixels out of a photo in pure QML is a maze: Canvas cannot
        draw an Image *item* (Qt 6 dropped that), cannot resolve the
        itemgrabber: URL a grab result carries, and loadImage on the photo's
        own URL would decode the entire file a second time. What does work:
        grab the already-decoded item at 8x8, save that postage stamp to the
        cache directory, and let the Canvas load those hundred bytes back.
    */
    readonly property string samplePath:
        StandardPaths.writableLocation(StandardPaths.CacheLocation)
            .toString().replace("file://", "")
        + "/nx-nebula-glow-" + card.cardIndex + ".png"

    function requestGlowSample(): void {
        if (card.frameStyle < 1 || card.front.status !== Image.Ready) {
            return;
        }
        try {
            card.front.grabToImage(result => {
                if (result.saveToFile(card.samplePath)) {
                    sampler.loadImage("file://" + card.samplePath);
                }
            }, Qt.size(sampler.width, sampler.height));
        } catch (err) {
            card.glowColor = "#7700ff";
        }
    }

    onImageSourceChanged: {
        if (String(imageSource).length === 0) {
            return;
        }
        if (back.source == imageSource) {
            // The hidden slot already holds this picture — a two-image
            // folder lands here every other turn. Bring it forward rather
            // than dropping the turn, or the rotation visibly stalls.
            if (back.status === Image.Ready) {
                card.promote(back);
            } else if (back.status === Image.Error) {
                card.sourceFailed();
            }
            return;
        }
        card.generation += 1;
        back.generation = card.generation;
        back.source = imageSource;
        // A picture already in the pixmap cache is Ready the moment it is
        // assigned and will never emit statusChanged.
        if (back.status === Image.Ready) {
            card.promote(back);
        }
    }

    /*
        One of the two cross-fading pictures.

        In pan-and-scan the item is deliberately 10% larger than the card and
        crops to it, which leaves 5% of slack on each side for the Translate
        to travel through. Only transform properties move.
    */
    component Slot: Image {
        id: slot

        property bool shown: false
        property int generation: 0

        readonly property bool panning: card.fitMode === 2
        readonly property real over: panning ? 1.10 : 1.0
        readonly property real sign: (generation % 2 === 0) ? 1 : -1
        readonly property int panPeriod: 45000 + (generation % 4) * 15000
        property real zoom: 0

        anchors.centerIn: parent
        width: parent.width * over
        height: parent.height * over
        fillMode: card.fitMode === 0 ? Image.PreserveAspectFit : Image.PreserveAspectCrop
        // Exactly one axis is capped, so Qt never has to guess whether the
        // pair means "fit inside" or "stretch to".
        sourceSize.width: card.fitMode === 0 ? 0 : card.capW
        sourceSize.height: card.fitMode === 0 ? card.capH : 0
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        // Cameras store portrait shots sideways plus an EXIF flag; without
        // this Qt shows them the way the sensor saw them.
        autoTransform: true
        opacity: shown ? 1 : 0
        scale: 1 + zoom

        transform: Translate { id: pan }

        Behavior on opacity {
            NumberAnimation { duration: 800; easing.type: Easing.InOutQuad }
        }

        onStatusChanged: {
            if (status === Image.Ready && !slot.shown) {
                card.promote(slot);
            } else if (status === Image.Error && !slot.shown) {
                // Only the hidden slot: the front picture decoded once and
                // cannot go bad, so this is always the incoming one.
                card.sourceFailed();
            }
        }

        SequentialAnimation {
            id: panX
            running: slot.panning
            paused: slot.panning && !card.live
            loops: Animation.Infinite
            onStopped: pan.x = 0
            NumberAnimation { target: pan; property: "x"; from: 0; to: card.width * 0.05 * slot.sign; duration: slot.panPeriod / 2; easing.type: Easing.InOutSine }
            NumberAnimation { target: pan; property: "x"; from: card.width * 0.05 * slot.sign; to: 0; duration: slot.panPeriod / 2; easing.type: Easing.InOutSine }
        }

        SequentialAnimation {
            running: slot.panning
            paused: slot.panning && !card.live
            loops: Animation.Infinite
            onStopped: pan.y = 0
            NumberAnimation { target: pan; property: "y"; from: 0; to: card.height * 0.04 * -slot.sign; duration: slot.panPeriod * 0.68; easing.type: Easing.InOutSine }
            NumberAnimation { target: pan; property: "y"; from: card.height * 0.04 * -slot.sign; to: 0; duration: slot.panPeriod * 0.68; easing.type: Easing.InOutSine }
        }

        SequentialAnimation {
            running: slot.panning
            paused: slot.panning && !card.live
            loops: Animation.Infinite
            onStopped: slot.zoom = 0
            NumberAnimation { target: slot; property: "zoom"; from: 0; to: 0.06; duration: slot.panPeriod * 0.9; easing.type: Easing.InOutSine }
            NumberAnimation { target: slot; property: "zoom"; from: 0.06; to: 0; duration: slot.panPeriod * 0.9; easing.type: Easing.InOutSine }
        }
    }

    Canvas {
        id: sampler

        width: 8
        height: 8
        visible: false
        renderStrategy: Canvas.Immediate
        renderTarget: Canvas.Image
        onImageLoaded: sampler.requestPaint()
        onPaint: {
            const grabbed = "file://" + card.samplePath;
            if (!sampler.isImageLoaded(grabbed)) {
                return;
            }
            try {
                const ctx = sampler.getContext("2d");
                ctx.clearRect(0, 0, sampler.width, sampler.height);
                ctx.drawImage(grabbed, 0, 0, sampler.width, sampler.height);
                const d = ctx.getImageData(0, 0, sampler.width, sampler.height).data;

                // Weighted circular mean of the hue; the weight is chroma
                // times mid-lightness, so greys and blown highlights say
                // nothing and one saturated subject decides.
                let xs = 0;
                let ys = 0;
                let total = 0;
                for (let i = 0; i < d.length; i += 4) {
                    const r = d[i] / 255;
                    const g = d[i + 1] / 255;
                    const b = d[i + 2] / 255;
                    const hi = Math.max(r, g, b);
                    const lo = Math.min(r, g, b);
                    const c = hi - lo;
                    if (c < 0.06) {
                        continue;
                    }
                    let h;
                    if (hi === r) {
                        h = ((g - b) / c + 6) % 6;
                    } else if (hi === g) {
                        h = (b - r) / c + 2;
                    } else {
                        h = (r - g) / c + 4;
                    }
                    h *= Math.PI / 3;
                    const weight = c * (1 - Math.abs(hi + lo - 1));
                    xs += weight * Math.cos(h);
                    ys += weight * Math.sin(h);
                    total += weight;
                }
                if (total > 1.5) {
                    let hue = Math.atan2(ys, xs) / (2 * Math.PI);
                    if (hue < 0) {
                        hue += 1;
                    }
                    card.glowColor = Qt.hsla(hue, 0.85, 0.55, 1);
                } else {
                    card.glowColor = "#7700ff";
                }
            } catch (err) {
                card.glowColor = "#7700ff";
            }
            sampler.unloadImage(grabbed);
        }
    }

    // The halo behind a square tile. Declared before the plate so the glow
    // stays underneath; the rounded style gets its bloom from GlassSurface
    // instead.
    Loader {
        anchors.fill: parent
        active: card.frameStyle === 1 && card.effectsPossible
        source: "BloomHalo.qml"
        onLoaded: item.tint = Qt.binding(() => card.glowColor)
    }

    // The plate is the whole card: lit edge plus picture. When the glass
    // treatment is on it stops painting itself and becomes a texture for
    // GlassSurface to round off and drop a shadow under.
    Item {
        id: plate
        anchors.fill: parent
        visible: !card.glassActive
        layer.enabled: card.glassActive

        Rectangle {
            anchors.fill: parent
            radius: card.glassActive ? card.frameRadius : 0
            // DESIGN --edge-lit, collapsed from 147deg to vertical: Rectangle
            // gradients cannot run diagonally, and the light still arrives
            // from above.
            gradient: Gradient {
                GradientStop { position: 0.00; color: Qt.rgba(0.886, 0.784, 1.0, 0.62) }
                GradientStop { position: 0.30; color: Qt.rgba(0.604, 0.235, 1.0, 0.28) }
                GradientStop { position: 0.58; color: Qt.rgba(0.0, 0.898, 1.0, 0.10) }
                GradientStop { position: 1.00; color: Qt.rgba(0.0, 0.0, 0.0, 0.30) }
            }
        }

        Item {
            id: content
            anchors.fill: parent
            anchors.margins: 1
            clip: true

            Slot { id: imgA; shown: card.useA }
            Slot { id: imgB; shown: !card.useA }
        }
    }

    Loader {
        id: glassLoader
        anchors.fill: parent
        active: card.frameStyle === 2 && card.effectsPossible
        source: "GlassSurface.qml"
        onLoaded: {
            item.plate = plate;
            item.cornerRadius = Qt.binding(() => card.frameRadius);
            item.tint = Qt.binding(() => card.glowColor);
        }
    }
}
