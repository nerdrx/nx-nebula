/*
    SPDX-FileCopyrightText: 2026 nerdrx

    SPDX-License-Identifier: GPL-3.0-or-later

    The photo layer that sits over the nebula.

    The problem it exists to solve: a 32:9 monitor and a folder of portrait
    photos. "Fill" crops a portrait down to a letterbox slice of itself;
    "fit" leaves one lonely stamp adrift in a field of nothing. So on a very
    wide screen this lays out two or three photos as a row of equal-height
    glass cards, each keeping its own aspect ratio, and rotates them one at a
    time on a stagger. Mixed shapes pack instead of leaving ragged holes
    (DESIGN §5, §11), and the nebula shows through between them.

    Everything animated is a transform or an opacity.
*/

import QtQuick
import Qt.labs.folderlistmodel

Item {
    id: gallery

    property string folder: ""
    property int fitMode: 0
    property int backdrop: 0
    property bool glassFrame: true
    property bool ultrawide: true
    property int interval: 300
    property bool shuffle: true
    property bool live: true

    /** True when the photos hide the nebula completely; it can stop drawing. */
    readonly property bool covered: cardsReady
        && (backdrop !== 0 || (activeSlots === 1 && fitMode !== 0))

    readonly property real aspect: height > 0 ? width / height : 1.78

    /*
        How many photos to show at once.

        Only in "fit" — the whole point is that nothing gets cropped — and
        only past roughly 21:9, where a single fitted photo starts to look
        stranded. 21:9 gets two, 32:9 gets three, and three is the ceiling:
        past that they are postage stamps.
    */
    readonly property int slotCount: (!ultrawide || fitMode !== 0 || aspect < 2.1)
        ? 1
        : Math.max(2, Math.min(3, Math.round(aspect / 1.15)))

    readonly property int activeSlots: Math.max(1, Math.min(slotCount, Math.max(1, files.count)))

    readonly property bool cardsReady: card0.loaded
        && (activeSlots < 2 || card1.loaded)
        && (activeSlots < 3 || card2.loaded)

    readonly property url folderUrl: {
        const raw = String(gallery.folder);
        if (raw.length === 0) {
            return "";
        }
        return raw.indexOf("://") > 0 ? raw : "file://" + raw;
    }

    // --- layout -----------------------------------------------------------
    // 8px rhythm (DESIGN §7). Cards share one height and take their width
    // from their own aspect, so the row is dense whatever shapes turn up.
    readonly property real gap: 24
    readonly property real sideMargin: 32
    /** In "fit" the card *is* the photo, so it never crops; otherwise it is
        the whole screen and the photo crops to it. */
    readonly property bool framed: fitMode === 0
    readonly property real aspectSum: (activeSlots > 0 ? card0.aspect : 0)
        + (activeSlots > 1 ? card1.aspect : 0)
        + (activeSlots > 2 ? card2.aspect : 0)
    readonly property real availW: Math.max(1, width - sideMargin * 2 - gap * (activeSlots - 1))
    readonly property real cardH: Math.min(height * (activeSlots === 1 ? 0.88 : 0.80),
                                           availW / Math.max(0.01, aspectSum))
    readonly property real frameRadius: Math.max(12, Math.min(32, Math.round(18 * height / 1080)))

    // --- playlist ---------------------------------------------------------

    property var playlist: []
    property int cursor: 0
    property int turn: 0

    /*
        How many decode failures a single turn may chase before giving up.

        A card that cannot decode its picture asks for the next one, which
        may itself be broken; the budget is one full lap of the playlist per
        turn, so every good file gets a chance and a folder of nothing but
        broken files comes to rest instead of spinning forever.
    */
    property int skipBudget: 0

    function skipFailed(slot: int): void {
        if (gallery.skipBudget <= 0) {
            return;
        }
        gallery.skipBudget -= 1;
        gallery.fill(slot);
    }

    function rebuild(): void {
        const n = files.count;
        let order = [];
        for (let i = 0; i < n; ++i) {
            order.push(i);
        }
        if (gallery.shuffle) {
            for (let i = n - 1; i > 0; --i) {
                const j = Math.floor(Math.random() * (i + 1));
                const swap = order[i];
                order[i] = order[j];
                order[j] = swap;
            }
        }
        gallery.playlist = order;
        gallery.cursor = 0;
        gallery.turn = 0;
        gallery.skipBudget = n;
        for (let s = 0; s < 3; ++s) {
            gallery.fill(s);
        }
    }

    function takeNext(): url {
        if (gallery.playlist.length === 0) {
            return "";
        }
        const idx = gallery.playlist[gallery.cursor % gallery.playlist.length];
        gallery.cursor = (gallery.cursor + 1) % gallery.playlist.length;
        return files.get(idx, "fileUrl");
    }

    function fill(slot: int): void {
        if (slot >= gallery.activeSlots) {
            return;
        }
        const target = slot === 0 ? card0 : (slot === 1 ? card1 : card2);
        target.imageSource = gallery.takeNext();
    }

    FolderListModel {
        id: files
        folder: gallery.folderUrl
        // AVIF and JPEG XL decode wherever kimageformats is installed, which
        // on Plasma is nearly everywhere; where it is not, the decode fails
        // and the skip budget quietly steps past them.
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp", "*.avif", "*.jxl"]
        caseSensitive: false
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
        onStatusChanged: {
            if (status === FolderListModel.Ready) {
                gallery.rebuild();
            }
        }
    }

    onShuffleChanged: {
        if (files.status === FolderListModel.Ready) {
            gallery.rebuild();
        }
    }

    onActiveSlotsChanged: {
        gallery.skipBudget = gallery.playlist.length;
        for (let s = 0; s < 3; ++s) {
            gallery.fill(s);
        }
    }

    // One slot at a time, so the wall never blinks all at once. Each card
    // still sits for the full interval; the changes are just interleaved.
    Timer {
        running: gallery.live && gallery.visible && gallery.playlist.length > gallery.activeSlots
        repeat: true
        interval: Math.max(5, gallery.interval / gallery.activeSlots) * 1000
        onTriggered: {
            gallery.skipBudget = gallery.playlist.length;
            gallery.fill(gallery.turn);
            gallery.turn = (gallery.turn + 1) % gallery.activeSlots;
        }
    }

    // --- backdrop ---------------------------------------------------------

    // "dim": DESIGN --bg-top with the same vignette the nebula wears.
    Item {
        anchors.fill: parent
        visible: gallery.backdrop === 2 && gallery.cardsReady

        Rectangle {
            anchors.fill: parent
            color: "#0a0714"
        }
        Image {
            anchors.fill: parent
            source: "../images/vignette.png"
            fillMode: Image.Stretch
            smooth: true
            asynchronous: true
        }
    }

    // "blur": a 64px decode scaled up is already a passable gaussian and
    // costs nothing, so it is the floor. BlurBackdrop refines it when
    // QtQuick.Effects is there.
    Item {
        anchors.fill: parent
        visible: gallery.backdrop === 1 && gallery.cardsReady
        clip: true

        Image {
            anchors.fill: parent
            source: card0.imageSource
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 64
            smooth: true
            asynchronous: true
            cache: false
            clip: true
        }
        Rectangle {
            anchors.fill: parent
            color: "#0a0714"
            opacity: 0.55
        }
        Loader {
            anchors.fill: parent
            // Same software-scene-graph guard as the glass frame; the cheap
            // upscale underneath is already a usable blur on its own.
            active: gallery.backdrop === 1 && GraphicsInfo.api !== GraphicsInfo.Software
            source: "BlurBackdrop.qml"
            onLoaded: item.imageSource = Qt.binding(() => card0.imageSource)
        }
        // The same falloff the nebula wears, so a photo backdrop and a nebula
        // backdrop darken toward the edges identically.
        Image {
            anchors.fill: parent
            source: "../images/vignette.png"
            fillMode: Image.Stretch
            smooth: true
            asynchronous: true
        }
    }

    // --- the photos -------------------------------------------------------

    Row {
        anchors.centerIn: parent
        spacing: gallery.gap

        GalleryCard {
            id: card0
            visible: true
            width: gallery.framed ? gallery.cardH * aspect : gallery.width
            height: gallery.framed ? gallery.cardH : gallery.height
            fitMode: gallery.fitMode
            // A full-bleed photo has no edges to light and no corners to
            // round; the frame belongs to cards floating on the nebula.
            glass: gallery.glassFrame && gallery.framed
            frameRadius: gallery.frameRadius
            live: gallery.live
            onSourceFailed: gallery.skipFailed(0)
        }

        GalleryCard {
            id: card1
            visible: gallery.activeSlots > 1
            width: gallery.cardH * aspect
            height: gallery.cardH
            fitMode: gallery.fitMode
            glass: gallery.glassFrame && gallery.framed
            frameRadius: gallery.frameRadius
            live: gallery.live
            onSourceFailed: gallery.skipFailed(1)
        }

        GalleryCard {
            id: card2
            visible: gallery.activeSlots > 2
            width: gallery.cardH * aspect
            height: gallery.cardH
            fitMode: gallery.fitMode
            glass: gallery.glassFrame && gallery.framed
            frameRadius: gallery.frameRadius
            live: gallery.live
            onSourceFailed: gallery.skipFailed(2)
        }
    }
}
