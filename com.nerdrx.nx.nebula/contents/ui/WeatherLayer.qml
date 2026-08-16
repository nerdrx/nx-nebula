/*
    SPDX-FileCopyrightText: 2026 nerdrx

    SPDX-License-Identifier: GPL-3.0-or-later

    The sky wears your weather.

    Strictly opt-in: nothing here runs, and no request leaves the machine,
    until the user has switched it on and typed coordinates in by hand. The
    only endpoint is Open-Meteo (open data, no key, no account), asked once
    every half hour for four numbers: cloud cover, rain, showers, snowfall.

    What the numbers do: cloud cover raises a drifting two-layer veil and
    dims the stars through NebulaLayer's `clarity` (which also grounds the
    meteors, the aurora and the comet — you cannot watch a shower through
    overcast). Rain is a sparse fall of streaks, snow a slow sway of
    flakes; both are a handful of quads on transform-and-opacity, like
    everything else in this wallpaper. If a fetch fails, the sky simply
    keeps the last weather it knew.
*/

import QtQuick

Item {
    id: weather

    property bool enabled: false
    property real latitude: 0
    property real longitude: 0
    property bool live: true

    /** Test hook: point it at a file:// JSON shaped like the real answer. */
    property string endpoint: "https://api.open-meteo.com/v1/forecast"

    property real cloudCover: 0   // 0..1
    property real rain: 0         // 0..1
    property real snow: 0         // 0..1

    /** What the stars see through this. 1 = clear night. */
    readonly property real clarity: 1 - 0.75 * cloudCover

    Behavior on cloudCover { NumberAnimation { duration: 5000; easing.type: Easing.InOutQuad } }
    Behavior on rain { NumberAnimation { duration: 3000 } }
    Behavior on snow { NumberAnimation { duration: 3000 } }

    function refresh(): void {
        if (!weather.enabled) {
            return;
        }
        // The query belongs on the real service only; the file:// test hook
        // is read as-is.
        let url = weather.endpoint;
        if (url.indexOf("http") === 0) {
            url += "?latitude=" + weather.latitude
                + "&longitude=" + weather.longitude
                + "&current=cloud_cover,rain,showers,snowfall";
        }
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            try {
                const cur = JSON.parse(xhr.responseText).current;
                weather.cloudCover = Math.max(0, Math.min(1, (cur.cloud_cover || 0) / 100));
                weather.rain = Math.max(0, Math.min(1, ((cur.rain || 0) + (cur.showers || 0)) / 4));
                weather.snow = Math.max(0, Math.min(1, (cur.snowfall || 0) / 2));
            } catch (err) {
                // keep the last sky we knew
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    Timer {
        running: weather.enabled && weather.live
        repeat: true
        triggeredOnStart: true
        interval: 1800000
        onTriggered: weather.refresh()
    }

    onEnabledChanged: {
        if (!weather.enabled) {
            weather.cloudCover = 0;
            weather.rain = 0;
            weather.snow = 0;
        }
    }

    // ------------------------------------------------------------- the veil

    // Two copies of one billow sprite, drifting on unrelated periods, the
    // upper one mirrored — overcast without a visible seam or repeat.
    Image {
        id: cloudsA
        source: "../images/clouds.png"
        anchors.centerIn: parent
        width: parent.width * 1.45
        height: parent.height * 1.15
        fillMode: Image.Stretch
        smooth: true
        asynchronous: true
        visible: opacity > 0.004
        opacity: 0.50 * weather.cloudCover
        transform: Translate { id: cloudDriftA }

        SequentialAnimation {
            running: true
            paused: !(weather.live && weather.cloudCover > 0.02)
            loops: Animation.Infinite
            NumberAnimation { target: cloudDriftA; property: "x"; from: 0; to: weather.width * 0.04; duration: 90000; easing.type: Easing.InOutSine }
            NumberAnimation { target: cloudDriftA; property: "x"; from: weather.width * 0.04; to: -weather.width * 0.04; duration: 180000; easing.type: Easing.InOutSine }
            NumberAnimation { target: cloudDriftA; property: "x"; from: -weather.width * 0.04; to: 0; duration: 90000; easing.type: Easing.InOutSine }
        }
    }

    Image {
        id: cloudsB
        source: "../images/clouds.png"
        anchors.centerIn: parent
        width: parent.width * 1.5
        height: parent.height * 1.2
        fillMode: Image.Stretch
        mirror: true
        smooth: true
        asynchronous: true
        visible: opacity > 0.004
        opacity: 0.38 * weather.cloudCover
        transform: Translate { id: cloudDriftB }

        SequentialAnimation {
            running: true
            paused: !(weather.live && weather.cloudCover > 0.02)
            loops: Animation.Infinite
            NumberAnimation { target: cloudDriftB; property: "x"; from: 0; to: -weather.width * 0.05; duration: 127000; easing.type: Easing.InOutSine }
            NumberAnimation { target: cloudDriftB; property: "x"; from: -weather.width * 0.05; to: weather.width * 0.05; duration: 254000; easing.type: Easing.InOutSine }
            NumberAnimation { target: cloudDriftB; property: "x"; from: weather.width * 0.05; to: 0; duration: 127000; easing.type: Easing.InOutSine }
        }
    }

    // ------------------------------------------------------------- the rain

    Repeater {
        model: 18

        delegate: Rectangle {
            id: drop

            required property int index

            width: Math.max(1, Math.round(weather.height * 0.0012))
            height: weather.height * (0.035 + 0.015 * (index % 3))
            radius: width
            rotation: 7
            visible: weather.rain > 0.01
            opacity: weather.rain * (0.30 + 0.12 * (index % 3))
            y: -height
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.62, 0.72, 0.85, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0.62, 0.72, 0.85, 0.75) }
            }

            SequentialAnimation {
                running: weather.live && weather.rain > 0.01
                loops: Animation.Infinite
                ScriptAction {
                    script: {
                        drop.x = Math.random() * weather.width;
                        fall.duration = 650 + Math.random() * 400;
                    }
                }
                PauseAnimation { duration: (drop.index * 137) % 500 }
                NumberAnimation {
                    id: fall
                    target: drop
                    property: "y"
                    from: -drop.height
                    to: weather.height + drop.height
                }
            }
        }
    }

    // ------------------------------------------------------------- the snow

    Repeater {
        model: 20

        delegate: Rectangle {
            id: flake

            required property int index

            width: Math.max(2, Math.round(weather.height * (0.003 + 0.0015 * (index % 3))))
            height: width
            radius: width / 2
            color: "#e8e6f4"
            visible: weather.snow > 0.01
            opacity: weather.snow * (0.35 + 0.15 * (index % 4))
            y: -height
            transform: Translate { id: sway }

            SequentialAnimation {
                running: weather.live && weather.snow > 0.01
                loops: Animation.Infinite
                ScriptAction {
                    script: {
                        flake.x = Math.random() * weather.width;
                        drift.duration = 6500 + Math.random() * 4500;
                    }
                }
                PauseAnimation { duration: (flake.index * 331) % 2000 }
                NumberAnimation {
                    id: drift
                    target: flake
                    property: "y"
                    from: -flake.height
                    to: weather.height + flake.height
                }
            }

            SequentialAnimation {
                running: weather.live && weather.snow > 0.01
                loops: Animation.Infinite
                NumberAnimation { target: sway; property: "x"; from: 0; to: 18; duration: 1900 + (flake.index % 5) * 300; easing.type: Easing.InOutSine }
                NumberAnimation { target: sway; property: "x"; from: 18; to: 0; duration: 1900 + (flake.index % 5) * 300; easing.type: Easing.InOutSine }
            }
        }
    }
}
