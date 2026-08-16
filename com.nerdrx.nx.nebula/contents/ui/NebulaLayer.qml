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

    /** An aurora on the deepest nights, once or twice an hour. */
    property bool aurora: true

    /** The celestial bodies: the moon in its true phase, the Milky Way on
        the deepest nights, the evening star at dusk, a rare comet. */
    property bool celestials: true

    /** Southern sky: the seasons flip, and so does the moon — a southern
        observer sees it wax on the left. */
    property bool southern: false

    /** What the sky has to say tonight, or nothing. Fed to the clock's
        almanac line; refreshed by the minute tick. */
    property string almanacText: ""

    /** The real stars, wheeling about the celestial pole at sidereal rate,
        in place of the authored far starfield. */
    property bool realSky: false

    /** How clear the sky is, 0..1. Fed by the weather layer when the user
        opts in; 1 means tonight is whatever the almanac promised. */
    property real clarity: 1

    /** Which of the baked moon frames shows tonight: 0-15 the phases,
        16 the eclipsed blood moon, 17 the blue moon. */
    property int moonFrame: 0

    /** Where the real sky has wheeled to, in degrees. */
    property real skyAngle: 0

    /** Local sidereal angle, approximately: local civil time stands in for
        UT, so the absolute orientation is off by the timezone while the
        *rate* — the thing you can actually watch — is exact. */
    function siderealDeg(when: date): real {
        const d = (when.getTime() - 946728000000) / 86400000;   // since J2000 noon
        const h = when.getHours() + when.getMinutes() / 60;
        return (100.46 + 0.9856474 * d + 15 * h) % 360;
    }

    /** The lunar eclipses through 2030, by date. On these nights the full
        moon turns copper for the whole night — the hours-long umbra pass,
        stylised to the wallpaper's timescale. */
    readonly property var lunarEclipses: [
        [2026, 3, 3], [2026, 8, 28], [2028, 1, 12], [2028, 7, 6],
        [2028, 12, 31], [2029, 6, 26], [2029, 12, 20], [2030, 6, 15]
    ]

    function isEclipseNight(when: date): bool {
        return nebula.lunarEclipses.some(e => e[0] === when.getFullYear()
            && e[1] === when.getMonth() + 1 && e[2] === when.getDate());
    }

    /** A second full moon in one calendar month. The five-day guard keeps
        one full moon's two-day frame from counting itself twice. */
    function isBlueMoon(when: date): bool {
        if (nebula.moonPhaseFrame(when) !== 8) {
            return false;
        }
        for (let d = 1; d < when.getDate() - 5; ++d) {
            if (nebula.moonPhaseFrame(new Date(when.getFullYear(), when.getMonth(), d, 12)) === 8) {
                return true;
            }
        }
        return false;
    }

    function moonPhaseFrame(when: date): int {
        // The synodic month, counted from a known new moon
        // (2000-01-06 18:14 UTC). Off by at most half a day from the
        // almanac, which for a sixteen-frame moon is exact.
        const synodic = 2551442876.9;
        const epoch = 947182440000;
        const t = ((when.getTime() - epoch) % synodic + synodic) % synodic;
        return Math.round(t / synodic * 16) % 16;
    }

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

    /** How far the year has pushed dawn and dusk, in hours. Summer nights
        arrive late and winter ones early — a ±1.2h swing about the
        equinoxes, mirrored on the southern half of the planet. Not a solar
        ephemeris, just the season's shape; the exact hours would need a
        location, and a wallpaper has no business asking for one. */
    function seasonalShift(when: date): real {
        const start = new Date(when.getFullYear(), 0, 1);
        const doy = Math.floor((when - start) / 86400000);
        const s = 1.2 * Math.cos(2 * Math.PI * (doy - 172) / 365.25);
        return nebula.southern ? -s : s;
    }

    function skyFactor(when: date): real {
        const smooth = t => {
            t = Math.max(0, Math.min(1, t));
            return t * t * (3 - 2 * t);
        };
        const h = when.getHours() + when.getMinutes() / 60;
        const shift = nebula.seasonalShift(when);
        const dawn = 5.5 - shift;    // two-hour ramps start here...
        const dusk = 19.5 + shift;   // ...and here
        let day;
        if (h < dawn) {
            day = 0;
        } else if (h < dawn + 2) {
            day = smooth((h - dawn) / 2);
        } else if (h < dusk) {
            day = 1;
        } else if (h < dusk + 2) {
            day = 1 - smooth((h - dusk) / 2);
        } else {
            day = 0;
        }
        return 1 - day;
    }

    /*
        The almanac: one short line when the sky has something to say —
        a shower's peak night, the moon at full or new, the year's turning
        points. Silence on ordinary nights is the whole point.
    */
    function almanacFor(when: date): string {
        if (nebula.isEclipseNight(when)) {
            return "Lunar eclipse tonight";
        }
        const day = new Date(when.getFullYear(), when.getMonth(), when.getDate());
        for (const peak of nebula.showerPeaks) {
            const nearest = new Date(when.getFullYear(), peak[0] - 1, peak[1]);
            if (Math.abs(day - nearest) < 43200000) {
                return "The " + peak[2] + " tonight";
            }
        }
        const frame = nebula.moonPhaseFrame(when);
        if (frame === 8) {
            return nebula.isBlueMoon(when) ? "Blue moon" : "Full moon";
        }
        if (frame === 0) {
            return "New moon";
        }
        // One evening of anticipation before a peak; still nothing on the
        // truly ordinary nights.
        const tomorrow = new Date(when.getFullYear(), when.getMonth(), when.getDate() + 1);
        for (const peak of nebula.showerPeaks) {
            if (tomorrow.getMonth() + 1 === peak[0] && tomorrow.getDate() === peak[1]) {
                return "The " + peak[2] + " tomorrow";
            }
        }
        const md = (when.getMonth() + 1) * 100 + when.getDate();
        if (md === 320 || md === 922) {
            return "Equinox";
        }
        if (md === 1221) {
            return nebula.southern ? "The shortest night" : "The longest night";
        }
        if (md === 621) {
            return nebula.southern ? "The longest night" : "The shortest night";
        }
        return "";
    }

    // Per-minute steps through a two-hour ramp move this by well under a
    // percent, so no Behavior is needed — the sky just is the right sky.
    // Runs whenever the wallpaper is alive, not only when the day/night
    // *look* is on: the celestial bodies follow the real clock either way.
    Timer {
        running: nebula.animating
        repeat: true
        triggeredOnStart: true
        interval: 60000
        onTriggered: {
            const now = new Date();
            nebula.night = nebula.skyFactor(now);
            nebula.almanacText = nebula.almanacFor(now);
            nebula.skyAngle = nebula.siderealDeg(now);
            let frame = nebula.moonPhaseFrame(now);
            if (nebula.isEclipseNight(now)) {
                frame = 16;
            } else if (frame === 8 && nebula.isBlueMoon(now)) {
                frame = 17;
            }
            nebula.moonFrame = frame;
        }
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
        opacity: (base + wobble) * nebula.clarity

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

        /*
            The Milky Way, behind the star points where it belongs — it is
            made of stars too distant to resolve. A reward for the deepest
            night hours: it only rises past nightfall's last ramp, peaks at
            a few percent opacity, and drifts even more slowly than the
            starfields above it.
        */
        Image {
            id: milkyway
            source: "../images/milkyway.png"
            anchors.centerIn: parent
            width: parent.width * 1.35
            height: parent.height * 0.95
            rotation: -16
            fillMode: Image.Stretch
            smooth: true
            asynchronous: true
            visible: nebula.celestials && opacity > 0.004
            opacity: 0.07 * Math.max(0, Math.min(1, (nebula.night - 0.70) / 0.22)) * nebula.clarity
            transform: Translate { id: mwDrift }

            SequentialAnimation {
                running: true
                paused: !nebula.animating
                loops: Animation.Infinite
                NumberAnimation { target: mwDrift; property: "x"; from: 0; to: nebula.unit * 0.006; duration: Math.round(105000 / nebula.speed); easing.type: Easing.InOutSine }
                NumberAnimation { target: mwDrift; property: "x"; from: nebula.unit * 0.006; to: -nebula.unit * 0.006; duration: Math.round(210000 / nebula.speed); easing.type: Easing.InOutSine }
                NumberAnimation { target: mwDrift; property: "x"; from: -nebula.unit * 0.006; to: 0; duration: Math.round(105000 / nebula.speed); easing.type: Easing.InOutSine }
            }
        }

        /*
            The real sky. The Yale catalog to fourth magnitude, projected
            about the celestial pole and wheeling at sidereal rate — a
            quarter degree a minute, invisible in the moment, unmistakable
            across an evening. The minute tick supplies the angle and a
            linear minute-long rotation glides between values, so the wheel
            turns instead of ticking. It replaces the authored far field;
            the near stars and twinklers stay for sparkle.
        */
        Image {
            id: realsky
            source: nebula.southern ? "../images/realsky-south.png" : "../images/realsky-north.png"

            readonly property real span: nebula.unit * 2.6

            width: span
            height: span
            x: nebula.width * 0.76 - span / 2
            y: nebula.height * 0.10 - span / 2
            rotation: (nebula.southern ? 1 : -1) * nebula.skyAngle
            smooth: true
            asynchronous: true
            visible: nebula.realSky
            opacity: 0.92 * (0.88 + 0.24 * nebula.nightNow) * nebula.clarity

            Behavior on rotation {
                RotationAnimation {
                    duration: 60000
                    direction: RotationAnimation.Shortest
                }
            }
        }

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
            visible: !nebula.realSky
            // 0.85 at the neutral point, brighter after dusk, dimmer by day.
            opacity: 0.85 * (0.88 + 0.24 * nebula.nightNow) * nebula.clarity
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
            opacity: Math.min(1, 0.90 + 0.24 * nebula.nightNow) * nebula.clarity
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
            The moon, in its true phase.

            The sheet holds sixteen baked phases; sourceClipRect picks
            tonight's, refreshed by the same minute tick that moves the sky.
            It hangs in the upper right — away from the violet mass and the
            clock — fades in as real night settles, and drifts a whisper so
            an OLED never holds it still. A new moon is, correctly, almost
            nothing: a dark disc you only notice if you look for it.
        */
        Image {
            id: moon
            source: "../images/moon.png"

            readonly property real span: nebula.unit * 0.052

            width: span
            height: span
            x: nebula.width * 0.815 - span / 2
            y: nebula.height * 0.17 - span / 2
            sourceClipRect: Qt.rect(nebula.moonFrame * 384, 0, 384, 384)
            // A southern moon waxes on the left.
            mirror: nebula.southern
            smooth: true
            asynchronous: true
            visible: nebula.celestials && opacity > 0.004
            opacity: 0.85 * Math.max(0, Math.min(1, (nebula.night - 0.55) / 0.20))
                * (0.30 + 0.70 * nebula.clarity)   // the moon burns through thin cloud
            transform: Translate { id: moonDrift }

            SequentialAnimation {
                running: true
                paused: !nebula.animating
                loops: Animation.Infinite
                NumberAnimation { target: moonDrift; property: "x"; from: 0; to: -nebula.unit * 0.008; duration: Math.round(140000 / nebula.speed); easing.type: Easing.InOutSine }
                NumberAnimation { target: moonDrift; property: "x"; from: -nebula.unit * 0.008; to: nebula.unit * 0.008; duration: Math.round(280000 / nebula.speed); easing.type: Easing.InOutSine }
                NumberAnimation { target: moonDrift; property: "x"; from: nebula.unit * 0.008; to: 0; duration: Math.round(140000 / nebula.speed); easing.type: Easing.InOutSine }
            }
        }

        /*
            The evening star. It rises through dusk, hangs in the west, and
            sets before the night is truly deep — a twilight bump driven
            entirely by the sky factor, no timers of its own. Deliberately
            steady: planets do not twinkle.
        */
        Image {
            id: venus
            source: "../images/star-bright.png"

            readonly property real span: nebula.unit * 0.020
            readonly property real dusk: Math.max(0, Math.min(1, (nebula.night - 0.22) / 0.20))
                * (1 - Math.max(0, Math.min(1, (nebula.night - 0.72) / 0.16)))

            width: span
            height: span
            x: nebula.width * 0.735 - span / 2
            // Setting: it slides gently down as the night deepens.
            y: nebula.height * (0.30 + 0.24 * nebula.night) - span / 2
            smooth: true
            asynchronous: true
            visible: nebula.celestials && opacity > 0.004
            opacity: 0.9 * dusk * nebula.clarity
        }

        /*
            The nova: the once-in-a-blue-moon tier. Every four hours the sky
            rolls a quiet die; a few times a month, on a dark clear night,
            one new star swells over a minute to outshine everything, then
            takes half an hour to die. Most owners will see it once and
            wonder if they imagined it. No almanac line — it is a secret.
        */
        Image {
            id: nova
            source: "../images/star-bright.png"
            width: nebula.unit * 0.030
            height: width
            opacity: 0
            visible: nebula.celestials && opacity > 0
        }

        SequentialAnimation {
            id: novaShow
            paused: novaShow.running && !nebula.animating
            NumberAnimation { target: nova; property: "opacity"; from: 0; to: 0.95; duration: 60000; easing.type: Easing.InOutSine }
            NumberAnimation { target: nova; property: "opacity"; to: 0; duration: 1800000; easing.type: Easing.InQuad }
        }

        Timer {
            id: novaClock
            running: nebula.celestials && nebula.animating
            repeat: true
            interval: 14400000
            onTriggered: {
                if (Math.random() < 0.033 && nebula.skyFactor(new Date()) >= 0.5
                        && nebula.clarity >= 0.45) {
                    nebula.novaNow();
                }
            }
        }

        /*
            The comet: the rarest thing this sky does. Once every few hours
            the scheduler considers one, and only a dark sky gets it — a
            long, slow crossing over a couple of minutes, tail trailing,
            violet head running out into a cyan tail.
        */
        Image {
            id: comet
            source: "../images/comet.png"
            width: nebula.unit * 0.30
            height: width * 0.25
            smooth: true
            asynchronous: true
            opacity: 0
            visible: nebula.celestials && opacity > 0
        }

        ParallelAnimation {
            id: cometFlight
            paused: cometFlight.running && !nebula.animating

            NumberAnimation { id: cometX; target: comet; property: "x"; easing.type: Easing.Linear }
            NumberAnimation { id: cometY; target: comet; property: "y"; easing.type: Easing.Linear }
            SequentialAnimation {
                NumberAnimation { id: cometIn; target: comet; property: "opacity"; from: 0; to: 0.8; easing.type: Easing.InOutSine }
                NumberAnimation { id: cometHold; target: comet; property: "opacity"; to: 0.8 }
                NumberAnimation { id: cometOut; target: comet; property: "opacity"; to: 0; easing.type: Easing.InOutSine }
            }
        }

        Timer {
            id: cometClock
            running: nebula.celestials && nebula.animating
            repeat: true
            interval: 7200000 + Math.round(Math.random() * 14400000)   // 2 to 6 hours
            onTriggered: {
                if (nebula.skyFactor(new Date()) >= 0.5 && nebula.clarity >= 0.45) {
                    nebula.cometNow();
                }
                interval = 7200000 + Math.round(Math.random() * 14400000);
            }
        }

        /*
            The aurora curtain, hidden until an event.

            It hangs in front of the stars — aurora is atmosphere, stars are
            not — and behind the meteors, which burn far below it. An event
            is a slow arrival, a couple of minutes of gentle shimmering
            drift, and a slow dissolve; between events the item is invisible
            and costs nothing. Deep night only: the scheduler consults
            skyFactor directly, so it follows the real clock even when the
            day/night *look* is switched off.
        */
        Image {
            id: auroraCurtain
            source: "../images/aurora.png"
            fillMode: Image.Stretch
            smooth: true
            asynchronous: true
            opacity: 0
            visible: nebula.aurora && opacity > 0
            transform: Translate { id: auroraDrift }
        }

        ParallelAnimation {
            id: auroraShow
            paused: auroraShow.running && !nebula.animating

            NumberAnimation {
                id: auroraSlide
                target: auroraDrift
                property: "x"
                easing.type: Easing.InOutSine
            }
            SequentialAnimation {
                NumberAnimation { id: auroraIn; target: auroraCurtain; property: "opacity"; from: 0; easing.type: Easing.InOutSine }
                NumberAnimation { id: auroraDim; target: auroraCurtain; property: "opacity"; easing.type: Easing.InOutSine }
                NumberAnimation { id: auroraSwell; target: auroraCurtain; property: "opacity"; easing.type: Easing.InOutSine }
                NumberAnimation { id: auroraOut; target: auroraCurtain; property: "opacity"; to: 0; easing.type: Easing.InOutSine }
            }
        }

        // Once every 12 to 35 minutes the sky *considers* an aurora, and
        // only deep night gets one. The re-roll happens whether or not the
        // curtain rose, so a wallpaper left running all day cannot save up
        // a burst of them for dusk.
        Timer {
            id: auroraClock
            running: nebula.aurora && nebula.animating
            repeat: true
            interval: 720000 + Math.round(Math.random() * 1380000)
            onTriggered: {
                if (nebula.skyFactor(new Date()) >= 0.65 && nebula.clarity >= 0.45) {
                    nebula.auroraNow();
                }
                interval = 720000 + Math.round(Math.random() * 1380000);
            }
        }

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
                // Overcast skies show no meteors; the schedule keeps
                // rolling so a clearing sky picks straight back up.
                if (nebula.clarity >= 0.45) {
                    nebula.meteorNow();
                }
                interval = nebula.nextMeteorDelay(new Date());
            }
        }

        /*
            A satellite: the meteor's slow, faithful opposite.

            A three-pixel dot that takes twenty-odd seconds to cross the sky
            in a dead-straight line, brightening and dimming once mid-pass
            the way a tumbling body catches the sun. It shares the meteors
            switch — they are the same hobby.
        */
        Rectangle {
            id: satellite
            width: Math.max(2, Math.round(nebula.unit * 0.0016))
            height: width
            radius: width / 2
            color: "#e8e4f8"
            opacity: 0
            visible: nebula.meteors && opacity > 0
        }

        ParallelAnimation {
            id: satPass
            paused: satPass.running && !nebula.animating

            NumberAnimation { id: satX; target: satellite; property: "x"; easing.type: Easing.Linear }
            NumberAnimation { id: satY; target: satellite; property: "y"; easing.type: Easing.Linear }
            SequentialAnimation {
                NumberAnimation { id: satIn; target: satellite; property: "opacity"; from: 0; to: 0.35; easing.type: Easing.InOutSine }
                NumberAnimation { id: satFlare; target: satellite; property: "opacity"; to: 0.8; easing.type: Easing.InOutSine }
                NumberAnimation { id: satFade; target: satellite; property: "opacity"; to: 0.35; easing.type: Easing.InOutSine }
                NumberAnimation { id: satOut; target: satellite; property: "opacity"; to: 0; easing.type: Easing.InOutSine }
            }
        }

        // Every 6 to 18 minutes, one quiet pass.
        Timer {
            id: satClock
            running: nebula.meteors && nebula.animating
            repeat: true
            interval: 360000 + Math.round(Math.random() * 720000)
            onTriggered: {
                if (nebula.clarity >= 0.45) {
                    nebula.satelliteNow();
                }
                interval = 360000 + Math.round(Math.random() * 720000);
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
        [1, 3, "Quadrantids"],
        [4, 22, "Lyrids"],
        [5, 6, "Eta Aquariids"],
        [7, 30, "Delta Aquariids"],
        [8, 12, "Perseids"],
        [10, 21, "Orionids"],
        [11, 17, "Leonids"],
        [12, 14, "Geminids"],
        [12, 22, "Ursids"]
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

        // No two alike: length and peak brightness vary per flight, faint
        // short ones outnumbering the occasional long bright earthgrazer.
        meteor.width = nebula.unit * (0.05 + Math.random() * 0.05);
        flare.to = 0.65 + Math.random() * 0.35;

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

    /** How long until the next meteor. Pure in `when`, random in amplitude:
        quiet nights wait minutes, shower peaks wait seconds — and for the
        first quarter hour of the new year the sky simply celebrates. */
    function nextMeteorDelay(when: date): int {
        if (when.getMonth() === 0 && when.getDate() === 1
                && when.getHours() === 0 && when.getMinutes() < 15) {
            return 2500 + Math.round(Math.random() * 2500);
        }
        return nebula.showerRadiant(when) >= 0
            ? 12000 + Math.round(Math.random() * 18000)
            : 45000 + Math.round(Math.random() * 105000);
    }

    /** Raise the aurora once, immediately. The deep-night scheduler's entry
        point, public for the same reason meteorNow is. */
    function auroraNow(): void {
        // A broad veil across the upper sky, sized to the frame the way the
        // sprite was authored: about 1.3 scale-units wide, half as tall.
        const w = nebula.unit * (1.15 + Math.random() * 0.35);
        const h = w * 0.5;
        auroraCurtain.width = w;
        auroraCurtain.height = h;
        auroraCurtain.x = nebula.width * (0.30 + Math.random() * 0.40) - w / 2;
        auroraCurtain.y = nebula.height * (0.16 + Math.random() * 0.14) - h / 2;
        auroraCurtain.rotation = -8 + Math.random() * 16;

        const life = 120000 + Math.round(Math.random() * 120000);
        const peak = 0.09 + Math.random() * 0.06;   // sprite contract: <= 0.14ish

        auroraSlide.from = 0;
        auroraSlide.to = nebula.unit * (Math.random() < 0.5 ? 0.03 : -0.03);
        auroraSlide.duration = life;

        auroraIn.to = peak;
        auroraIn.duration = Math.round(life * 0.15);
        auroraDim.to = peak * 0.72;                 // one slow shimmer
        auroraDim.duration = Math.round(life * 0.28);
        auroraSwell.to = peak;
        auroraSwell.duration = Math.round(life * 0.27);
        auroraOut.duration = life - auroraIn.duration
            - auroraDim.duration - auroraSwell.duration;
        auroraShow.restart();
    }

    /** Light the nova once, immediately. */
    function novaNow(): void {
        nova.x = nebula.width * (0.10 + Math.random() * 0.80) - nova.width / 2;
        nova.y = nebula.height * (0.08 + Math.random() * 0.50) - nova.height / 2;
        novaShow.restart();
    }

    /** Fly the comet once, immediately. The scheduler's entry point, public
        like the others so a harness can see one without waiting hours. */
    function cometNow(): void {
        const toRad = Math.PI / 180;
        // Shallower and far slower than any meteor: 8-22 degrees, and the
        // crossing takes a minute and a half to three minutes.
        const pitch = 8 + Math.random() * 14;
        const angle = Math.random() < 0.5 ? pitch : 180 - pitch;
        const dist = nebula.unit * (0.45 + Math.random() * 0.25);
        const dx = Math.cos(angle * toRad) * dist;
        const dy = Math.sin(angle * toRad) * dist;
        const sx = nebula.width * (0.15 + Math.random() * 0.70) - comet.width / 2 - dx / 2;
        const sy = nebula.height * (0.10 + Math.random() * 0.35) - dy / 2;
        const life = 90000 + Math.round(Math.random() * 90000);

        comet.rotation = angle;
        cometX.from = sx;
        cometX.to = sx + dx;
        cometX.duration = life;
        cometY.from = sy;
        cometY.to = sy + dy;
        cometY.duration = life;
        cometIn.duration = Math.round(life * 0.15);
        cometHold.duration = Math.round(life * 0.55);
        cometOut.duration = life - cometIn.duration - cometHold.duration;
        cometFlight.restart();
    }

    /** Fly one satellite pass, immediately. */
    function satelliteNow(): void {
        // Border to border on a shallow chord, either direction.
        const leftToRight = Math.random() < 0.5;
        const sy = nebula.height * (0.10 + Math.random() * 0.55);
        const ey = sy + nebula.height * (Math.random() * 0.30 - 0.15);
        const life = 16000 + Math.round(Math.random() * 12000);

        satX.from = leftToRight ? -satellite.width : nebula.width;
        satX.to = leftToRight ? nebula.width : -satellite.width;
        satX.duration = life;
        satY.from = sy;
        satY.to = ey;
        satY.duration = life;

        satIn.duration = Math.round(life * 0.12);
        satFlare.duration = Math.round(life * 0.30);
        satFade.duration = Math.round(life * 0.30);
        satOut.duration = life - satIn.duration - satFlare.duration - satFade.duration;
        satPass.restart();
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
