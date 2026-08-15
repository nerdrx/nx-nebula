/*
    SPDX-FileCopyrightText: 2026 nerdrx

    SPDX-License-Identifier: GPL-3.0-or-later

    Wallpaper configuration page. Follows the Kirigami.FormLayout contract the
    stock plugins use: a `cfg_<Key>` property per entry in config/main.xml,
    `twinFormLayouts: parentLayout` so the labels line up with the rest of the
    dialog, and `formLayout` exposed for the same reason.
*/

import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root

    twinFormLayouts: parentLayout
    property var parentLayout
    property alias formLayout: root

    property alias cfg_Animate: animate.checked
    property bool cfg_AnimateDefault: true

    property int cfg_Speed: 100
    property int cfg_SpeedDefault: 100

    property alias cfg_Twinkle: twinkle.checked
    property bool cfg_TwinkleDefault: true

    property alias cfg_Meteors: meteors.checked
    property bool cfg_MeteorsDefault: true

    property alias cfg_DayNight: dayNight.checked
    property bool cfg_DayNightDefault: true

    property alias cfg_Aurora: aurora.checked
    property bool cfg_AuroraDefault: true

    property int cfg_Mode: 0
    property int cfg_ModeDefault: 0

    property string cfg_GalleryFolder: ""
    property string cfg_GalleryFolderDefault: ""

    property int cfg_Interval: 300
    property int cfg_IntervalDefault: 300

    property alias cfg_Shuffle: shuffle.checked
    property bool cfg_ShuffleDefault: true

    property int cfg_FitMode: 0
    property int cfg_FitModeDefault: 0

    property int cfg_Backdrop: 0
    property int cfg_BackdropDefault: 0

    property alias cfg_GlassFrame: glassFrame.checked
    property bool cfg_GlassFrameDefault: true

    property alias cfg_UltrawideGallery: ultrawide.checked
    property bool cfg_UltrawideGalleryDefault: true

    property alias cfg_ShowClock: showClock.checked
    property bool cfg_ShowClockDefault: true

    property int cfg_ClockPosition: 0
    property int cfg_ClockPositionDefault: 0

    property int cfg_TimeFormat: 0
    property int cfg_TimeFormatDefault: 0

    readonly property string dom: "plasma_wallpaper_com.nerdrx.nx.nebula"
    readonly property bool galleryOn: cfg_Mode === 1
    readonly property bool fitOn: galleryOn && cfg_FitMode === 0

    // ------------------------------------------------------------ background

    Kirigami.Separator {
        Kirigami.FormData.label: i18nd(root.dom, "Background")
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: animate
        Kirigami.FormData.label: i18nd(root.dom, "Nebula:")
        text: i18nd(root.dom, "Drift the clouds")
    }

    RowLayout {
        Kirigami.FormData.label: i18nd(root.dom, "Speed:")
        enabled: animate.checked
        spacing: Kirigami.Units.smallSpacing

        QQC2.Slider {
            id: speed
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            from: 25
            // 100 is the livelier default; 25 restores DESIGN §3's original
            // 60–110s subliminal drift for anyone who wants the wall to sit
            // still until they look for it.
            to: 300
            stepSize: 5
            snapMode: QQC2.Slider.SnapAlways
            value: root.cfg_Speed
            onMoved: root.cfg_Speed = value
        }

        QQC2.Label {
            // toFixed is locale-independent by definition; no toLocaleString
            // anywhere in a logic path (DESIGN §7).
            text: (root.cfg_Speed / 100).toFixed(2) + "×"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 3
        }
    }

    QQC2.CheckBox {
        id: twinkle
        Kirigami.FormData.label: i18nd(root.dom, "Stars:")
        text: i18nd(root.dom, "Let a few of them breathe")
    }

    QQC2.CheckBox {
        id: meteors
        // Meteors are motion, so they obey the master animation switch
        // exactly like the drift does.
        enabled: animate.checked
        text: i18nd(root.dom, "Shooting stars, and the odd slow satellite")
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        enabled: animate.checked && meteors.checked
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        text: i18nd(root.dom,
            "On a real shower's peak night — the Perseids, the Geminids — they "
            + "arrive every half minute or so, all along one shared radiant.")
    }

    QQC2.CheckBox {
        id: dayNight
        Kirigami.FormData.label: i18nd(root.dom, "Sky:")
        text: i18nd(root.dom, "Deeper nights, softer days")
    }

    QQC2.CheckBox {
        id: aurora
        enabled: animate.checked
        text: i18nd(root.dom, "An aurora on the deepest nights")
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        enabled: dayNight.checked
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        text: i18nd(root.dom,
            "Stars brighten and twinkle a little harder late at night and ease "
            + "off in the daytime. A few percent either way — the sky keeps its "
            + "character.")
    }

    // --------------------------------------------------------------- gallery

    Kirigami.Separator {
        Kirigami.FormData.label: i18nd(root.dom, "Photographs")
        Kirigami.FormData.isSection: true
    }

    QQC2.ComboBox {
        id: mode
        Kirigami.FormData.label: i18nd(root.dom, "Show:")
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        textRole: "label"
        model: [
            { label: i18nd(root.dom, "Nebula only") },
            { label: i18nd(root.dom, "Nebula and a photo folder") }
        ]
        currentIndex: root.cfg_Mode
        onActivated: root.cfg_Mode = currentIndex
    }

    RowLayout {
        Kirigami.FormData.label: i18nd(root.dom, "Folder:")
        enabled: root.galleryOn
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            readOnly: true
            text: root.cfg_GalleryFolder
            placeholderText: i18nd(root.dom, "No folder chosen")
        }

        QQC2.Button {
            icon.name: "folder-open"
            text: i18ndc(root.dom, "@action:button Pick a folder of images", "Choose…")
            onClicked: folderDialog.open()
        }
    }

    FolderDialog {
        id: folderDialog
        title: i18ndc(root.dom, "@title:window", "Choose a Photo Folder")
        currentFolder: {
            if (root.cfg_GalleryFolder.length > 0) {
                return root.cfg_GalleryFolder;
            }
            const pictures = StandardPaths.standardLocations(StandardPaths.PicturesLocation);
            return pictures.length > 0 ? pictures[0] : "";
        }
        onAccepted: root.cfg_GalleryFolder = selectedFolder
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: i18nd(root.dom, "Change every:")
        enabled: root.galleryOn
        from: 5
        to: 86400
        stepSize: 30
        value: root.cfg_Interval
        onValueModified: root.cfg_Interval = value
        textFromValue: (value) => i18ndp(root.dom, "%1 second", "%1 seconds", value)
        valueFromText: (text) => parseInt(text.replace(/\D/g, ""), 10) || root.cfg_Interval
    }

    QQC2.CheckBox {
        id: shuffle
        Kirigami.FormData.label: i18nd(root.dom, "Order:")
        enabled: root.galleryOn
        text: i18nd(root.dom, "Shuffle")
    }

    // ----------------------------------------------------------- shape & fit

    Kirigami.Separator {
        Kirigami.FormData.label: i18nd(root.dom, "Fitting")
        Kirigami.FormData.isSection: true
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: i18nd(root.dom, "Shape:")
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        enabled: root.galleryOn
        textRole: "label"
        model: [
            { label: i18nd(root.dom, "Fit — never crop") },
            { label: i18nd(root.dom, "Fill — crop to the screen") },
            { label: i18nd(root.dom, "Pan and scan — crop, then drift slowly") }
        ]
        currentIndex: root.cfg_FitMode
        onActivated: root.cfg_FitMode = currentIndex
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: i18nd(root.dom, "Behind:")
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        enabled: root.fitOn
        textRole: "label"
        model: [
            { label: i18nd(root.dom, "The nebula") },
            { label: i18nd(root.dom, "A blurred copy of the photo") },
            { label: i18nd(root.dom, "Plain dark") }
        ]
        currentIndex: root.cfg_Backdrop
        onActivated: root.cfg_Backdrop = currentIndex
    }

    QQC2.CheckBox {
        id: glassFrame
        Kirigami.FormData.label: i18nd(root.dom, "Frame:")
        enabled: root.fitOn
        text: i18nd(root.dom, "Glass card with a lit edge")
    }

    QQC2.CheckBox {
        id: ultrawide
        enabled: root.fitOn
        text: i18nd(root.dom, "Side-by-side photos on very wide screens")
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        enabled: root.fitOn
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        text: i18nd(root.dom,
            "Past about 21:9 a single fitted photo looks stranded. This packs two "
            + "or three of them across instead, each keeping its own shape, and "
            + "changes them one at a time.")
    }

    // ----------------------------------------------------------------- clock

    Kirigami.Separator {
        Kirigami.FormData.label: i18nd(root.dom, "Clock")
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: showClock
        Kirigami.FormData.label: i18nd(root.dom, "Clock:")
        text: i18nd(root.dom, "Show the day, date and time")
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: i18nd(root.dom, "Position:")
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        enabled: showClock.checked
        textRole: "label"
        model: [
            { label: i18nd(root.dom, "Centre of the screen") },
            { label: i18nd(root.dom, "Top centre") }
        ]
        currentIndex: root.cfg_ClockPosition
        onActivated: root.cfg_ClockPosition = currentIndex
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: i18nd(root.dom, "Time:")
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        enabled: showClock.checked
        textRole: "label"
        model: [
            { label: i18nd(root.dom, "Follow the system language") },
            { label: i18nd(root.dom, "12-hour") },
            { label: i18nd(root.dom, "24-hour") }
        ]
        currentIndex: root.cfg_TimeFormat
        onActivated: root.cfg_TimeFormat = currentIndex
    }
}
