/*
    SPDX-FileCopyrightText: 2026 nerdrx

    SPDX-License-Identifier: GPL-3.0-or-later

    DESIGN.md §3, "The living background", as a Plasma wallpaper layer.

    Everything here is a pre-rendered sprite from tools/gen_nebula_layers.py.
    The only things that change per frame are transform properties, so the
    whole layer is a handful of textured quads and the GPU never re-rasterises
    anything. No ShaderEffect, no Canvas, no timers.

    Stacking order, bottom to top:

        field      Rectangle gradient  #0a0714 -> #12091f
        blobs      three drifting, breathing nebula bodies
        stars      two sparse layers, the near one drifting slightly faster
        vignette   edges darker than the centre
        grain      one bit of tiled dither, because Qt Quick does not dither
                   its own gradients and a near-black ramp bands without it
*/

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: nebula

    /** Master motion gate. False freezes every animation in place. */
    property bool animating: true

    /**
        Drift speed multiplier, 0.25 .. 3.0.

        1.0 is tuned so that watching the wall for half a minute tells you it
        is alive. DESIGN §3 asks for 60–110s periods, but that figure was set
        for a backdrop behind an app window, where the eye is busy elsewhere;
        on a bare desktop the same numbers read as a still image. 0.25 puts
        the periods back in the DESIGN range for anyone who wants the original
        subliminal drift.
    */
    property real speed: 1.0

    /** Slow opacity breathing on a sparse subset of the stars. */
    property bool twinkle: true

    /** A meteor every minute or two. Rare enough to stay an event. */
    property bool meteors: true

    /** Let the wall clock tune the sky: deeper nights, softer days. */
    property bool dayNight: true

    /*
        0 = full day, 1 = full night, refreshed once a minute.

        Everything driven by this is a multiplier that passes through 1.0 at
        0.5, so switching the feature off — which pins nightNow at 0.5 — gives
        exactly the sky this wallpaper always had, and the swings around it
        are a few percent either way: stars brighten and twinkle harder late
        at night, ease off by day, the nebula bodies glow a touch deeper in
        the dark. Dawn and dusk are fixed civil hours with smoothstep ramps;
        real solar times need a location, and a wallpaper has no business
        asking for one.
    */
    property real night: 0.5
    readonly property real nightNow: dayNight ? night : 0.5

    function skyFactor(when: date): real {
        const smooth = t => {
            t = Math.max(0, Math.min(1, t));
            return t * t * (3 - 2 * t);
        };
        const h = when.getHours() + when.getMinutes() / 60;
        let day;
        if (h < 5.5) {
            day = 0;
        } else if (h < 7.5) {
            day = smooth((h - 5.5) / 2);        // dawn
        } else if (h < 19.5) {
            day = 1;
        } else if (h < 21.5) {
            day = 1 - smooth((h - 19.5) / 2);   // dusk
        } else {
            day = 0;
        }
        return 1 - day;
    }

    // Per-minute steps through a two-hour ramp move this by well under a
    // percent, so no Behavior is needed — the sky just is the right sky.
    Timer {
        running: nebula.dayNight && nebula.animating
        repeat: true
        triggeredOnStart: true
        interval: 60000
        onTriggered: nebula.night = nebula.skyFactor(new Date())
    }

    /** True once every sprite has settled, one way or the other. */
    readonly property bool ready: [
        violet, cyan, magenta, starsFar, starsNear,
        twinkleA, twinkleB, twinkleC, vignette, grain
    ].every(layer => layer.status === Image.Ready || layer.status === Image.Error)

    // Blob sizes and drift amplitudes are expressed in "scale units" of
    // sqrt(w*h), exactly like tools/gen_wallpaper.py, so a 32:9 monitor gets
    // the same composition rather than a stretched or cropped one.
    readonly property real unit: Math.sqrt(Math.max(1, width) * Math.max(1, height))

    /*
        One nebula body.

        The sprite is baked axis-aligned in its own local frame; `spin` turns
        it into place, `relX`/`relY` put its centre in the frame, `spanUnits`
        and `blobOpacity` come straight out of the generator and must match
        contents/images/layers.json.

        Drift is a Translate, not a change of x/y, so it never touches
        geometry. The three-segment sequence starts and ends at zero offset,
        which means a frozen wallpaper sits exactly on the static composition.
    */
    component Blob: Image {
        id: blob

        property real relX: 0.5
        property real relY: 0.5
        property real spanUnits: 1.0
        property real spin: 0
        property real blobOpacity: 0.1

        property real amplitudeX: 0.03
        property real amplitudeY: 0.02
        property int periodX: 48000
        property int periodY: 58000
        property int periodBreathe: 57000
        property real breatheAmount: 0.035
        /** -1 makes this blob travel the opposite way round its ellipse. */
        property real direction: 1

        // Animated by the sequences below; kept separate from the bindings
        // above so an animation never fights a binding.
        property real breathe: 0

        // Every instance rolls its own ±8% on every period: two screens (or
        // desktop and lock screen) running this wallpaper must not breathe
        // in lockstep, and identical loops side by side read as one texture
        // copy-pasted rather than two skies.
        readonly property real jog: 0.92 + Math.random() * 0.16

        readonly property real ax: direction * amplitudeX * nebula.unit
        readonly property real ay: direction * amplitudeY * nebula.unit
        readonly property int qx: Math.max(16, Math.round(periodX * jog / 4 / nebula.speed))
        readonly property int qy: Math.max(16, Math.round(periodY * jog / 4 / nebula.speed))
        readonly property int qb: Math.max(16, Math.round(periodBreathe * jog / 4 / nebula.speed))

        width: nebula.unit * spanUnits
        height: width
        x: nebula.width * relX - width / 2
        y: nebula.height * relY - height / 2
        rotation: spin
        scale: 1 + breathe
        // ±7% around the authored value: a touch deeper in the dark.
        opacity: blobOpacity * (0.93 + 0.14 * nebula.nightNow)

        fillMode: Image.Stretch
        smooth: true
        mipmap: false
        cache: false
        asynchronous: true

        transform: Translate { id: drift }

        SequentialAnimation {
            running: true
            paused: !nebula.animating
            loops: Animation.Infinite
            NumberAnimation { target: drift; property: "x"; from: 0; to: blob.ax; duration: blob.qx; easing.type: Easing.InOutSine }
            NumberAnimation { target: drift; property: "x"; from: blob.ax; to: -blob.ax; duration: blob.qx * 2; easing.type: Easing.InOutSine }
            NumberAnimation { target: drift; property: "x"; from: -blob.ax; to: 0; duration: blob.qx; easing.type: Easing.InOutSine }
        }

        SequentialAnimation {
            running: true
            paused: !nebula.animating
            loops: Animation.Infinite
            NumberAnimation { target: drift; property: "y"; from: 0; to: blob.ay; duration: blob.qy; easing.type: Easing.InOutSine }
            NumberAnimation { target: drift; property: "y"; from: blob.ay; to: -blob.ay; duration: blob.qy * 2; easing.type: Easing.InOutSine }
            NumberAnimation { target: drift; property: "y"; from: -blob.ay; to: 0; duration: blob.qy; easing.type: Easing.InOutSine }
        }

        SequentialAnimation {
            running: true
            paused: !nebula.animating
            loops: Animation.Infinite
            NumberAnimation { target: blob; property: "breathe"; from: 0; to: blob.breatheAmount; duration: blob.qb; easing.type: Easing.InOutSine }
            NumberAnimation { target: blob; property: "breathe"; from: blob.breatheAmount; to: -blob.breatheAmount; duration: blob.qb * 2; easing.type: Easing.InOutSine }
            NumberAnimation { target: blob; property: "breathe"; from: -blob.breatheAmount; to: 0; duration: blob.qb; easing.type: Easing.InOutSine }
        }
    }

    /*
        One sparse sheet of twinkling stars.

        `base` is the resting opacity the generator's composite assumes, and
        the swing is symmetric around it, so a frozen or twinkle-off wallpaper
        shows exactly the picture in contents/screenshot.png. Nothing here
        moves — the drift belongs to the two layers above — and nothing but
        opacity changes.
    */
    component TwinkleLayer: Image {
        id: tw

        property int period: 6000
        property real base: 0.78
        property real swing: 0.22
        /** -1 starts the cycle dim instead of bright. */
        property real direction: 1

        property real wobble: 0
        readonly property real jog: 0.92 + Math.random() * 0.16
        // Stars twinkle a quarter harder late at night, a quarter softer by
        // day. The night-time peak can push a whisker past 1.0, where opacity
        // clamps: the brightest instant flattens rather than breaking.
        readonly property real reach: direction * swing * (0.75 + 0.5 * nebula.nightNow)
        readonly property int q: Math.max(16, Math.round(period * jog / 4 / nebula.speed))

        anchors.centerIn: parent
        width: parent.width * 1.05
        height: parent.height * 1.05
        fillMode: Image.PreserveAspectCrop
        clip: true
        smooth: true
        asynchronous: true
        visible: nebula.twinkle
        opacity: base + wobble

        SequentialAnimation {
            running: nebula.twinkle
            paused: nebula.twinkle && !nebula.animating
            loops: Animation.Infinite
            onStopped: tw.wobble = 0
            NumberAnimation { target: tw; property: "wobble"; from: 0; to: tw.reach; duration: tw.q; easing.type: Easing.InOutSine }
            NumberAnimation { target: tw; property: "wobble"; from: tw.reach; to: -tw.reach; duration: tw.q * 2; easing.type: Easing.InOutSine }
            NumberAnimation { target: tw; property: "wobble"; from: -tw.reach; to: 0; duration: tw.q; easing.type: Easing.InOutSine }
        }
    }

    // ---------------------------------------------------------------- field

    Rectangle {
        anchors.fill: parent
        // Four intermediate stops trace gen_wallpaper's t^1.15 ease, so the
        // darkest band hugs the top edge instead of marching down linearly.
        gradient: Gradient {
            GradientStop { position: 0.00; color: "#0a0714" }
            GradientStop { position: 0.25; color: "#0c0716" }
            GradientStop { position: 0.50; color: "#0e0819" }
            GradientStop { position: 0.75; color: "#10081c" }
            GradientStop { position: 1.00; color: "#12091f" }
        }
    }

    // ---------------------------------------------------------------- blobs

    // Violet leads from the upper left: it is the light source the whole
    // design language is lit by (DESIGN §1, §11).
    Blob {
        id: violet
        source: "../images/blob-violet.png"
        relX: 0.19; relY: 0.13
        spanUnits: 3.5100; spin: 28.0; blobOpacity: 0.18844
        amplitudeX: 0.030; amplitudeY: 0.022
        periodX: 48000; periodY: 58000
        periodBreathe: 57000; breatheAmount: 0.035
        direction: 1
    }

    // Cyan anchors the lower right and stays subordinate — light inside the
    // material, never a competing surface colour.
    Blob {
        id: cyan
        source: "../images/blob-cyan.png"
        relX: 0.84; relY: 0.87
        spanUnits: 2.7300; spin: -38.0; blobOpacity: 0.05200
        amplitudeX: 0.038; amplitudeY: 0.028
        periodX: 40000; periodY: 52000
        periodBreathe: 47000; breatheAmount: 0.030
        direction: -1
    }

    // A nearly subliminal magenta bloom holding the middle together.
    Blob {
        id: magenta
        source: "../images/blob-magenta.png"
        relX: 0.55; relY: 0.68
        spanUnits: 2.4180; spin: -68.0; blobOpacity: 0.03800
        amplitudeX: 0.032; amplitudeY: 0.040
        periodX: 55000; periodY: 36000
        periodBreathe: 53000; breatheAmount: 0.040
        direction: 1
    }

    // ---------------------------------------------------------------- stars

    Item {
        anchors.fill: parent
        clip: true

        Image {
            id: starsFar
            source: "../images/stars-far.png"
            anchors.centerIn: parent
            property real jog: 0.94 + Math.random() * 0.12
            // 5% overscan gives the drift somewhere to go without ever
            // exposing an edge.
            width: parent.width * 1.05
            height: parent.height * 1.05
            fillMode: Image.PreserveAspectCrop
            clip: true
            smooth: true
            asynchronous: true
            // 0.85 at the neutral point, brighter after dusk, dimmer by day.
            opacity: 0.85 * (0.88 + 0.24 * nebula.nightNow)
            transform: Translate { id: farDrift }

            SequentialAnimation {
                running: true
                paused: !nebula.animating
                loops: Animation.Infinite
                NumberAnimation { target: farDrift; property: "x"; from: 0; to: nebula.unit * 0.005; duration: Math.round(41000 * starsFar.jog / nebula.speed); easing.type: Easing.InOutSine }
                NumberAnimation { target: farDrift; property: "x"; from: nebula.unit * 0.005; to: -nebula.unit * 0.005; duration: Math.round(82000 * starsFar.jog / nebula.speed); easing.type: Easing.InOutSine }
                NumberAnimation { target: farDrift; property: "x"; from: -nebula.unit * 0.005; to: 0; duration: Math.round(41000 * starsFar.jog / nebula.speed); easing.type: Easing.InOutSine }
            }
        }

        Image {
            id: starsNear
            source: "../images/stars-near.png"
            anchors.centerIn: parent
            property real jog: 0.94 + Math.random() * 0.12
            width: parent.width * 1.05
            height: parent.height * 1.05
            fillMode: Image.PreserveAspectCrop
            clip: true
            smooth: true
            asynchronous: true
            // Full brightness from dusk on (the formula tops out just past
            // 1.0 and clamps); only the day softens the near field.
            opacity: Math.min(1, 0.90 + 0.24 * nebula.nightNow)
            transform: Translate { id: nearDrift }

            // Twice the throw and a shorter period than the far layer: the
            // only reason the two exist is that tiny parallax.
            SequentialAnimation {
                running: true
                paused: !nebula.animating
                loops: Animation.Infinite
                NumberAnimation { target: nearDrift; property: "x"; from: 0; to: nebula.unit * 0.010; duration: Math.round(30000 * starsNear.jog / nebula.speed); easing.type: Easing.InOutSine }
                NumberAnimation { target: nearDrift; property: "x"; from: nebula.unit * 0.010; to: -nebula.unit * 0.010; duration: Math.round(60000 * starsNear.jog / nebula.speed); easing.type: Easing.InOutSine }
                NumberAnimation { target: nearDrift; property: "x"; from: -nebula.unit * 0.010; to: 0; duration: Math.round(30000 * starsNear.jog / nebula.speed); easing.type: Easing.InOutSine }
            }
        }

        // Three sparse layers rather than one. A single layer can only fade
        // as a unit, which reads as the whole sky pulsing; three of them on
        // unrelated periods, the middle one counter-phased, read as
        // individual stars breathing. Cost: three opacity interpolators, and
        // opacity on a leaf Image is a uniform, not a repaint.
        TwinkleLayer { id: twinkleA; source: "../images/stars-twinkle-a.png"; period: 4300; direction: 1 }
        TwinkleLayer { id: twinkleB; source: "../images/stars-twinkle-b.png"; period: 6700; direction: -1 }
        TwinkleLayer { id: twinkleC; source: "../images/stars-twinkle-c.png"; period: 8900; direction: 1 }

        /*
            One meteor, reused for every flight.

            The streak is a hairline Rectangle whose gradient runs tail to
            head, so setting `rotation` aims the whole thing and a flight is
            x/y plus an opacity envelope on a single quad — nothing is ever
            re-rasterised. It lives inside the same clipped Item as the stars,
            at the same depth, and under the vignette like everything else.

            The travel is deliberately linear: a meteor moves at constant
            speed, and any easing here reads as the sky decelerating.
        */
        Rectangle {
            id: meteor

            width: nebula.unit * 0.075
            height: Math.max(1, Math.round(nebula.unit * 0.0011))
            radius: height / 2
            opacity: 0
            visible: nebula.meteors && opacity > 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                // Tail dissolves into the nebula's violet before it reaches
                // white: the streak should look lit by this sky, not pasted
                // over it.
                GradientStop { position: 0.00; color: Qt.rgba(0.72, 0.60, 1.00, 0.00) }
                GradientStop { position: 0.60; color: Qt.rgba(0.85, 0.78, 1.00, 0.55) }
                GradientStop { position: 0.94; color: Qt.rgba(1.00, 1.00, 1.00, 1.00) }
                GradientStop { position: 1.00; color: Qt.rgba(1.00, 1.00, 1.00, 0.00) }
            }
        }

        SequentialAnimation {
            id: flight
            paused: flight.running && !nebula.animating

            ParallelAnimation {
                NumberAnimation { id: flightX; target: meteor; property: "x"; easing.type: Easing.Linear }
                NumberAnimation { id: flightY; target: meteor; property: "y"; easing.type: Easing.Linear }
                SequentialAnimation {
                    NumberAnimation { id: flare; target: meteor; property: "opacity"; from: 0; to: 0.9; easing.type: Easing.OutQuad }
                    NumberAnimation { id: burnout; target: meteor; property: "opacity"; to: 0; easing.type: Easing.InQuad }
                }
            }
        }

        // 45s to 2.5min between flights, re-rolled every time so there is no
        // rhythm to catch — except on a real shower's peak night, when they
        // come every 12 to 30 seconds. Stops dead with the rest of the
        // motion; a flight already in the air pauses mid-streak and finishes
        // on return.
        Timer {
            id: meteorClock
            running: nebula.meteors && nebula.animating
            repeat: true
            interval: 45000 + Math.round(Math.random() * 105000)
            onTriggered: {
                nebula.meteorNow();
                interval = nebula.showerRadiant(new Date()) >= 0
                    ? 12000 + Math.round(Math.random() * 18000)
                    : 45000 + Math.round(Math.random() * 105000);
            }
        }
    }

    /*
        The major annual meteor showers, by peak night (month, day).

        Within a day and a half of a peak the scheduler above runs hot, and
        every flight leaves along one shared radiant — meteors in a shower are
        parallel, entering along the parent comet's orbit, and that coherence
        is what makes a shower look like a shower instead of a busy night.
    */
    readonly property var showerPeaks: [
        [1, 3],    // Quadrantids
        [4, 22],   // Lyrids
        [5, 6],    // Eta Aquariids
        [7, 30],   // Delta Aquariids
        [8, 12],   // Perseids
        [10, 21],  // Orionids
        [11, 17],  // Leonids
        [12, 14],  // Geminids
        [12, 22]   // Ursids
    ]

    /** The night's shared flight angle when a shower is peaking, else -1.
        Derived from the date, so it holds steady all night and every
        instance of the wallpaper agrees on it. */
    function showerRadiant(when: date): real {
        // Date-only distance: the peak day and one calendar day either side,
        // so the shower runs all of the peak night and its two shoulders no
        // matter what hour it is checked at. The seed comes from the *peak*,
        // not from today — a shower's radiant must not swing between its
        // nights, nor at midnight in the middle of one.
        const day = new Date(when.getFullYear(), when.getMonth(), when.getDate());
        for (const peak of nebula.showerPeaks) {
            const nearest = new Date(when.getFullYear(), peak[0] - 1, peak[1]);
            if (Math.abs(day - nearest) <= 1.05 * 86400000) {
                const seed = (peak[0] - 1) * 31 + peak[1];
                const pitch = 16 + (seed * 7) % 24;
                return (seed % 2 === 0) ? pitch : 180 - pitch;
            }
        }
        return -1;
    }

    /** Fire one meteor immediately. The scheduler's entry point, kept public
        because an offscreen harness cannot wait minutes for the real timer. */
    function meteorNow(): void {
        const toRad = Math.PI / 180;
        // Shallow and always downward; half the flights travel leftward —
        // unless a shower is peaking, in which case tonight's radiant rules
        // and each flight only scatters a few degrees around it.
        const radiant = nebula.showerRadiant(new Date());
        const pitch = 18 + Math.random() * 20;
        const angle = radiant >= 0
            ? radiant + (Math.random() * 12 - 6)
            : (Math.random() < 0.5 ? pitch : 180 - pitch);
        const dist = nebula.unit * (0.16 + Math.random() * 0.14);
        // Screen y grows downward, so +sin is down for either direction.
        const dx = Math.cos(angle * toRad) * dist;
        const dy = Math.sin(angle * toRad) * dist;
        // Upper half of the sky, biased away from the edges, and centred on
        // the flight so neither end starts already clipped.
        const sx = nebula.width * (0.08 + Math.random() * 0.84) - meteor.width / 2 - dx / 2;
        const sy = nebula.height * (0.06 + Math.random() * 0.42) - dy / 2;
        const life = 750 + Math.round(Math.random() * 500);

        meteor.rotation = angle;
        flightX.from = sx;
        flightX.to = sx + dx;
        flightX.duration = life;
        flightY.from = sy;
        flightY.to = sy + dy;
        flightY.duration = life;
        flare.duration = Math.round(life * 0.18);
        burnout.duration = life - flare.duration;
        flight.restart();
    }

    // ------------------------------------------------------- vignette, grain

    Image {
        id: vignette
        source: "../images/vignette.png"
        anchors.fill: parent
        // Stretched rather than cropped: the falloff is authored in
        // normalised frame coordinates, so stretching it *is* the correct
        // transform and the edges stay dark at any aspect ratio.
        fillMode: Image.Stretch
        smooth: true
        asynchronous: true
    }

    Image {
        id: grain
        source: "../images/grain.png"
        anchors.fill: parent
        fillMode: Image.Tile
        horizontalAlignment: Image.AlignLeft
        verticalAlignment: Image.AlignTop
        // Nearest sampling: the tile must land one texel per pixel or it
        // stops being a dither and starts being mush.
        smooth: false
        asynchronous: true
    }
}
