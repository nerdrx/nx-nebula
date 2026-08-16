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

    /** Show the photo's cleaned-up file name under the card. */
    property bool caption: false

    /** How much snow has settled on the tile, 0..1, from the weather. */
    property real snowCover: 0

    /** A specular sheen sweeps the glass now and then. */
    property bool sweepOn: true

    /** The halo breathes. */
    property bool bloomBreathe: true

    /** 1 while the pointer rests on this tile: a slight lift, a brighter
        glow, one sheen sweep on arrival. */
    property real attention: 0

    scale: 1 + 0.01 * attention

    Behavior on attention {
        NumberAnimation { duration: 400; easing.type: Easing.InOutQuad }
    }

    onAttentionChanged: {
        if (attention > 0.5 && card.sweepOn && card.live) {
            sweepAnim.restart();
        }
    }

    /** Glitch: random slice-displacement bursts, and one on each arrival. */
    property bool glitchSlices: false
    property bool glitchArrival: false

    function glitchBurst(): void {
        if (!card.live || card.front.status !== Image.Ready) {
            return;
        }
        for (let i = 0; i < sliceRep.count; ++i) {
            const sl = sliceRep.itemAt(i);
            sl.sy = Math.random() * 0.9;
            sl.sh = 0.02 + Math.random() * 0.06;
            sl.jitter = (Math.random() < 0.5 ? -1 : 1) * (4 + Math.random() * 14);
        }
        burstAnim.restart();
    }

    /** Corner radius, DESIGN --radius scaled to the screen. */
    property real frameRadius: 6

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

    // Sampling waits out the 800ms crossfade: a grab taken mid-fade sees
    // the picture at a fraction of its opacity and reads too dark.
    onUseAChanged: {
        sampleDelay.restart();
        if (card.glitchArrival) {
            arrivalGlitch.restart();
        }
    }

    Timer {
        id: arrivalGlitch
        interval: 150
        onTriggered: card.glitchBurst()
    }
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

        The file is named after the *photo's URL*, never reused for another
        picture: Qt's global pixmap cache keys on the URL and keeps serving
        the first pixels it ever saw for it, no matter what is on disk by
        then. With content-addressed names a cache hit is by definition the
        right answer, and one folder's worth of 130-byte stamps is nothing.
    */
    readonly property string sampleDir:
        StandardPaths.writableLocation(StandardPaths.CacheLocation)
            .toString().replace("file://", "")

    property string pendingSample: ""

    function requestGlowSample(): void {
        if (card.frameStyle < 1 || card.front.status !== Image.Ready) {
            return;
        }
        const path = card.sampleDir + "/nx-nebula-glow-"
            + Qt.md5(String(card.front.source)) + ".png";
        try {
            card.front.grabToImage(result => {
                if (result.saveToFile(path)) {
                    card.pendingSample = path;
                    sampler.loadImage("file://" + path);
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

        // Arrival settle: a new picture lands 1.5% large and eases down to
        // rest over a second, so it arrives instead of appearing. Transform
        // only, skipped entirely under reduced motion via the live gate.
        property real settle: 0

        onShownChanged: {
            if (slot.shown && card.live) {
                slot.settle = 0.015;
                settleBack.restart();
            }
        }

        NumberAnimation {
            id: settleBack
            target: slot
            property: "settle"
            to: 0
            duration: 1100
            easing.type: Easing.OutCubic
        }

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
        scale: 1 + zoom + settle

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
            if (card.pendingSample.length === 0) {
                return;
            }
            const grabbed = "file://" + card.pendingSample;
            if (!sampler.isImageLoaded(grabbed)) {
                return;
            }
            card.pendingSample = "";
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
    // instead. Oversized by the halo's own reach so the glow never has to
    // paint outside an item's bounds — see the note in BloomHalo.qml.
    Loader {
        anchors.fill: parent
        anchors.margins: item ? -item.reach : 0
        active: card.frameStyle === 1 && card.effectsPossible
        source: "BloomHalo.qml"
        onLoaded: {
            item.tint = Qt.binding(() => card.glowColor);
            item.breathe = Qt.binding(() => card.bloomBreathe && card.live);
            item.swellBoost = Qt.binding(() => 0.10 * card.attention);
        }
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

            /*
                Glitch slices: five clipped bands of the current photo,
                displaced sideways for a fraction of a second — the anatomy
                of a datamosh, in plain clipped Images. They share one
                cached decode and cost nothing while idle.
            */
            property real burstOn: 0

            Repeater {
                id: sliceRep
                model: 5
                delegate: Item {
                    property real sy: 0.2
                    property real sh: 0.04
                    property real jitter: 0
                    y: card.height * sy
                    width: card.width
                    height: Math.max(2, card.height * sh)
                    clip: true
                    visible: content.burstOn > 0.01
                    Image {
                        x: parent.jitter * content.burstOn
                        y: -parent.y
                        width: card.width
                        height: card.height
                        source: card.front.source
                        fillMode: card.front.fillMode
                        sourceSize: card.front.sourceSize
                        autoTransform: true
                        asynchronous: true
                        smooth: true
                    }
                }
            }

            SequentialAnimation {
                id: burstAnim
                NumberAnimation { target: content; property: "burstOn"; from: 0; to: 1; duration: 40 }
                PauseAnimation { duration: 90 }
                NumberAnimation { target: content; property: "burstOn"; to: 0.4; duration: 30 }
                PauseAnimation { duration: 60 }
                NumberAnimation { target: content; property: "burstOn"; to: 1; duration: 30 }
                PauseAnimation { duration: 110 }
                NumberAnimation { target: content; property: "burstOn"; to: 0; duration: 40 }
            }

            Timer {
                running: card.glitchSlices && card.live && card.loaded
                repeat: true
                interval: 180000 + Math.round(Math.random() * 300000)
                onTriggered: {
                    card.glitchBurst();
                    interval = 180000 + Math.round(Math.random() * 300000);
                }
            }

            /*
                The sheen: a soft diagonal band of light that sweeps the
                pane every couple of minutes, the way glass catches a
                moving light. Clipped by the content item; transform only.
            */
            Rectangle {
                id: sheen
                width: card.width * 0.5
                height: card.height * 2.4
                rotation: 24
                y: -card.height * 0.7
                x: -width * 1.5
                opacity: 0
                visible: card.sweepOn
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(0.95, 0.92, 1.0, 0.13) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }

            ParallelAnimation {
                id: sweepAnim
                paused: sweepAnim.running && !card.live
                NumberAnimation { target: sheen; property: "x"; from: -sheen.width * 1.5; to: card.width + sheen.width * 0.5; duration: 1600; easing.type: Easing.InOutQuad }
                SequentialAnimation {
                    NumberAnimation { target: sheen; property: "opacity"; from: 0; to: 1; duration: 400 }
                    PauseAnimation { duration: 800 }
                    NumberAnimation { target: sheen; property: "opacity"; to: 0; duration: 400 }
                }
            }

            Timer {
                running: card.sweepOn && card.live && card.loaded
                repeat: true
                interval: 90000 + Math.round(Math.random() * 180000)
                onTriggered: {
                    sweepAnim.restart();
                    interval = 90000 + Math.round(Math.random() * 180000);
                }
            }
        }
    }

    // Snow on the tile. It gathers along the top edge as the real snow
    // falls, and melts away after — the wall remembers the weather.
    Image {
        source: "../images/snowcap.png"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: -height * 0.35
        height: card.height * 0.05 * Math.min(1, card.snowCover * 1.4)
        fillMode: Image.Stretch
        smooth: true
        asynchronous: true
        visible: card.snowCover > 0.01
        opacity: 0.9 * Math.min(1, card.snowCover * 3)
    }

    /*
        The caption: the file name, dressed for the wall. Extension gone,
        separators to spaces, set in the same wide-tracked small type as the
        clock's date line and hung just under the card. It crossfades with
        the pictures because it reads the *front* slot.
    */
    Text {
        visible: card.caption
        anchors.top: parent.bottom
        anchors.topMargin: Math.max(10, Math.round(card.frameRadius * 0.7))
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: Math.round(font.letterSpacing / 2)
        text: {
            const name = decodeURIComponent(String(card.front.source).split("/").pop());
            return name.replace(/\.[^.]+$/, "").replace(/[_\-.]+/g, " ").trim().toUpperCase();
        }
        color: "#efeaff"
        opacity: 0.72
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.5)
        font.pixelSize: Math.max(10, Math.round(card.height * 0.022))
        font.weight: Font.Medium
        font.letterSpacing: Math.max(10, Math.round(card.height * 0.022)) * 0.3
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
            item.breathe = Qt.binding(() => card.bloomBreathe && card.live);
            item.swellBoost = Qt.binding(() => 0.10 * card.attention);
        }
    }
}
