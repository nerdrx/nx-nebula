/*
    SPDX-FileCopyrightText: 2026 nerdrx

    SPDX-License-Identifier: GPL-3.0-or-later

        T  H  U  R  S  D  A  Y
             06 AUG 2026
        ────────────────────────
            -  08:33 PM  -

    Weight and tracking do the branding; there are no webfonts anywhere in NX
    (DESIGN §1, §7). Legibility over a photograph comes from a 1px dark glyph
    outline plus a scrim that fades out vertically and has no horizontal edges
    at all — a rectangle with visible sides behind a clock would look like a
    widget, and this is meant to look like part of the wall.

    The tick realigns itself to the wall clock every time it fires, so it
    never drifts, and it asks for a wakeup once a minute rather than once a
    second: nothing on screen changes in between, and this is a desktop
    background.
*/

import QtQuick

Item {
    id: clock

    /** Gate: false stops the timer dead. */
    property bool active: true

    /** 0 = centred in the screen, 1 = up near the top. */
    property int position: 0

    /** Raised when the clock sits over photographs rather than the nebula. */
    property bool overPhotos: false

    readonly property real daySize: Math.max(18, Math.round(height * 0.075))
    readonly property real dateSize: Math.max(9, Math.round(height * 0.0165))
    readonly property real timeSize: Math.max(11, Math.round(height * 0.023))

    property string dayText: ""
    property string dateText: ""
    property string timeText: ""

    function pad(n: int): string {
        return (n < 10 ? "0" : "") + n;
    }

    function refresh(): void {
        const now = new Date();
        clock.dayText = Qt.formatDate(now, "dddd").toUpperCase();
        // Locale-aware month, but stripped of punctuation: several locales
        // render the short month as "Aug." and the trailing dot wrecks the
        // rhythm of the line. Digits are built by hand so no locale can
        // reformat them (DESIGN §7).
        const month = Qt.formatDate(now, "MMM").toUpperCase().replace(/[^\p{L}\p{N}]/gu, "");
        clock.dateText = clock.pad(now.getDate()) + " " + month + " " + now.getFullYear();

        let hour = now.getHours();
        const meridiem = hour < 12 ? "AM" : "PM";
        hour = hour % 12;
        if (hour === 0) {
            hour = 12;
        }
        clock.timeText = "– " + clock.pad(hour) + ":" + clock.pad(now.getMinutes())
            + " " + meridiem + " –";
    }

    Timer {
        id: tick
        running: clock.active && clock.visible
        repeat: true
        triggeredOnStart: true
        interval: 60000
        onTriggered: {
            clock.refresh();
            const now = new Date();
            // Land on the next minute boundary; from then on this is a
            // no-op that keeps the interval at a clean 60s.
            const remaining = 60000 - (now.getSeconds() * 1000 + now.getMilliseconds());
            tick.interval = remaining < 250 ? 60000 : remaining;
        }
    }

    // A soft horizontal wash. It fades to nothing top and bottom and runs
    // the full width, so it has no edge anywhere a viewer could catch.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: block.verticalCenter
        width: parent.width
        height: block.height * 3.2
        opacity: clock.overPhotos ? 1 : 0
        gradient: Gradient {
            GradientStop { position: 0.00; color: Qt.rgba(0.016, 0.008, 0.039, 0.0) }
            GradientStop { position: 0.28; color: Qt.rgba(0.016, 0.008, 0.039, 0.40) }
            GradientStop { position: 0.50; color: Qt.rgba(0.016, 0.008, 0.039, 0.50) }
            GradientStop { position: 0.72; color: Qt.rgba(0.016, 0.008, 0.039, 0.40) }
            GradientStop { position: 1.00; color: Qt.rgba(0.016, 0.008, 0.039, 0.0) }
        }

        Behavior on opacity {
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }
    }

    Column {
        id: block
        anchors.horizontalCenter: parent.horizontalCenter
        y: clock.position === 1
            ? Math.round(parent.height * 0.11)
            : Math.round((parent.height - height) / 2)
        spacing: Math.round(clock.daySize * 0.30)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            // Qt puts the letter spacing after the last glyph too, so a
            // centred tracked line reads half a space too far left.
            anchors.horizontalCenterOffset: Math.round(font.letterSpacing / 2)
            text: clock.dayText
            color: "#efeaff"
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.55)
            font.pixelSize: clock.daySize
            font.weight: Font.DemiBold
            font.letterSpacing: clock.daySize * 0.35
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: Math.round(font.letterSpacing / 2)
            text: clock.dateText
            color: "#efeaff"
            opacity: 0.86
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.5)
            font.pixelSize: clock.dateSize
            font.weight: Font.Medium
            font.letterSpacing: clock.dateSize * 0.34
        }

        // The one NX flourish: violet into cyan, fading out at both ends so
        // it is a hairline and not a rule (DESIGN §1 — no solid dividers).
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(clock.daySize * 5.2)
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.00; color: Qt.rgba(0.467, 0.0, 1.0, 0.0) }
                GradientStop { position: 0.30; color: Qt.rgba(0.467, 0.0, 1.0, 0.55) }
                GradientStop { position: 0.72; color: Qt.rgba(0.0, 0.898, 1.0, 0.42) }
                GradientStop { position: 1.00; color: Qt.rgba(0.0, 0.898, 1.0, 0.0) }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: Math.round(font.letterSpacing / 2)
            text: clock.timeText
            color: "#efeaff"
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.5)
            font.pixelSize: clock.timeSize
            font.weight: Font.Normal
            font.letterSpacing: clock.timeSize * 0.22
        }
    }
}
