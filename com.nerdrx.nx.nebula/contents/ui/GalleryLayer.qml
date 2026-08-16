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

    The folder is walked recursively (a photo library is a tree, not a
    directory), the row is packed by a small curator that knows the aspect
    of what is coming, and "one photo per day" turns the wall into a daily
    print that every screen agrees on.

    Everything animated is a transform or an opacity.
*/

import QtQuick
import Qt.labs.folderlistmodel

Item {
    id: gallery

    property string folder: ""
    property int fitMode: 0
    property int backdrop: 0
    /** 0 = plain lit tile, 1 = tile with a glow, 2 = rounded glass card. */
    property int frameStyle: 1
    property bool ultrawide: true
    property int interval: 300
    property bool shuffle: true
    property bool live: true
    /** Walk subfolders too. A photo library is rarely flat. */
    property bool recursive: true
    /** One deterministic photo per day instead of a rotation. */
    property bool daily: false
    /** Caption each photo with its cleaned-up file name. */
    property bool captions: false
    /** OLED care: wander the card row a few pixels over minutes. */
    property bool burnInGuard: true

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

    readonly property int activeSlots: Math.max(1, Math.min(slotCount, Math.max(1, library.length)))

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

    // --- the library ------------------------------------------------------
    /*
        A breadth-first walk of the folder tree, one FolderListModel step at
        a time (it can only list one directory, so it is pointed at each in
        turn). Depth and file caps keep a pathological tree from eating the
        session; hitting a cap is not an error, just a very large library.
        The walk restarts whenever the root folder changes on disk — cheap,
        and the only way to notice a new subfolder without watching every
        directory in the tree.
    */
    readonly property int maxDepth: 3
    readonly property int maxFiles: 2000

    property var library: []      // every image url found, as strings
    property var scanQueue: []    // {u: folder url, d: depth} still to walk
    property bool scanning: false
    property var walker: null     // the step's own FolderListModel

    /*
        One freshly created model per directory, folder set at birth. A
        reused model races: its previous listing's Ready can arrive after
        the folder property has already been repointed, delivering another
        directory's rows under the new name — the first victim being the
        model's implicit initial listing of the process's current directory,
        which for plasmashell is $HOME.
    */
    Component {
        id: walkerFactory

        FolderListModel {
            property int depth: 0
            property bool harvested: false

            nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp", "*.avif", "*.jxl"]
            caseSensitive: false
            showDirs: true
            showFiles: true
            showHidden: false
            sortField: FolderListModel.Name
            onStatusChanged: {
                if (status === FolderListModel.Ready) {
                    gallery.harvest();
                }
            }
        }
    }

    function startScan(): void {
        if (String(gallery.folderUrl).length === 0) {
            gallery.library = [];
            return;
        }
        gallery.scanQueue = [{ u: String(gallery.folderUrl), d: 0 }];
        gallery.library = [];
        gallery.scanning = true;
        gallery.advanceScan();
    }

    function advanceScan(): void {
        if (gallery.walker) {
            gallery.walker.destroy();
            gallery.walker = null;
        }
        if (gallery.scanQueue.length === 0 || gallery.library.length >= gallery.maxFiles) {
            gallery.scanning = false;
            gallery.rebuild();
            return;
        }
        const q = gallery.scanQueue.slice();
        const next = q.shift();
        gallery.scanQueue = q;
        gallery.walker = walkerFactory.createObject(gallery, { folder: next.u, depth: next.d });
    }

    function harvest(): void {
        // Signals from a superseded, not-yet-deleted walker end up here too;
        // only the current one, exactly once, gets to contribute.
        const w = gallery.walker;
        if (!gallery.scanning || !w || w.status !== FolderListModel.Ready || w.harvested) {
            return;
        }
        w.harvested = true;
        let found = gallery.library.slice();
        let q = gallery.scanQueue.slice();
        for (let i = 0; i < w.count && found.length < gallery.maxFiles; ++i) {
            if (w.get(i, "fileIsDir") === true) {
                if (gallery.recursive && w.depth + 1 <= gallery.maxDepth) {
                    q.push({ u: String(w.get(i, "fileUrl")), d: w.depth + 1 });
                }
            } else {
                found.push(String(w.get(i, "fileUrl")));
            }
        }
        gallery.library = found;
        gallery.scanQueue = q;
        gallery.advanceScan();
    }

    // The root watcher. Its rows are never read — the walker does that — but
    // FolderListModel watches its directory for free, and a change here is
    // the cue to walk the tree again.
    FolderListModel {
        id: rootWatch
        folder: gallery.folderUrl
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp", "*.avif", "*.jxl"]
        caseSensitive: false
        showDirs: true
        showFiles: true
        showHidden: false
        onStatusChanged: {
            if (status === FolderListModel.Ready) {
                gallery.startScan();
            }
        }
        onCountChanged: {
            if (status === FolderListModel.Ready) {
                rescanSoon.restart();
            }
        }
    }

    Timer {
        id: rescanSoon
        interval: 2500
        onTriggered: gallery.startScan()
    }

    onRecursiveChanged: gallery.startScan()

    // --- playlist ----------------------------------------------------------

    property var playlist: []   // urls, in play order
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
        // Sorted first: the daily pick and every other instance of this
        // wallpaper must agree on what "photo n" means.
        let order = gallery.library.slice().sort();
        if (gallery.shuffle && !gallery.daily) {
            for (let i = order.length - 1; i > 0; --i) {
                const j = Math.floor(Math.random() * (i + 1));
                const swap = order[i];
                order[i] = order[j];
                order[j] = swap;
            }
        }
        gallery.playlist = order;
        gallery.cursor = 0;
        gallery.turn = 0;
        gallery.skipBudget = order.length;
        for (let s = 0; s < 3; ++s) {
            gallery.fill(s);
        }
        gallery.scoutAhead();
    }

    function takeNext(): url {
        if (gallery.playlist.length === 0) {
            return "";
        }
        const u = gallery.playlist[gallery.cursor % gallery.playlist.length];
        gallery.cursor = (gallery.cursor + 1) % gallery.playlist.length;
        return u;
    }

    // --- the curator --------------------------------------------------------
    /*
        Aspect-aware packing. With two or three cards up, whichever photo
        comes next decides whether the row fills the width or leaves ragged
        margins. A tiny hidden Image walks ahead of the playlist decoding
        48px thumbnails just for their aspect ratio, and fill() then picks,
        from the next few photos, the one that brings the row closest to
        filling the available width at full height. Nothing is skipped —
        the winner is pulled forward and the others keep their turn.
    */
    property var aspectBook: ({})
    property var scoutList: []
    /** Rounds the head of the queue has lost the audition. A photo whose
        shape never suits the row would otherwise wait forever; after three
        losses it simply shows, and the row is imperfect for one turn. */
    property int frontLosses: 0

    Image {
        id: scout
        visible: false
        sourceSize.width: 48
        asynchronous: true
        cache: false
        autoTransform: true
        source: gallery.scoutList.length > 0 ? gallery.scoutList[0] : ""
        onStatusChanged: {
            if (gallery.scoutList.length === 0
                    || (status !== Image.Ready && status !== Image.Error)) {
                return;
            }
            gallery.aspectBook[String(gallery.scoutList[0])] =
                (status === Image.Ready && implicitHeight > 0)
                    ? implicitWidth / implicitHeight
                    : 1.5;
            gallery.scoutList = gallery.scoutList.slice(1);
        }
    }

    function scoutAhead(): void {
        if (gallery.daily || gallery.activeSlots < 2) {
            return;
        }
        const n = gallery.playlist.length;
        let want = [];
        for (let k = 0; k < Math.min(4, n); ++k) {
            const u = gallery.playlist[(gallery.cursor + k) % n];
            if (gallery.aspectBook[String(u)] === undefined) {
                want.push(u);
            }
        }
        gallery.scoutList = want;
    }

    function takeBest(slot: int): url {
        const n = gallery.playlist.length;
        if (n === 0) {
            return "";
        }
        if (gallery.activeSlots < 2 || !gallery.framed) {
            return gallery.takeNext();
        }
        let others = 0;
        if (slot !== 0) {
            others += card0.aspect;
        }
        if (slot !== 1 && gallery.activeSlots > 1) {
            others += card1.aspect;
        }
        if (slot !== 2 && gallery.activeSlots > 2) {
            others += card2.aspect;
        }
        const ideal = gallery.availW / Math.max(1, gallery.height * 0.80);
        let bestK = 0;
        let bestErr = Number.MAX_VALUE;
        for (let k = 0; k < Math.min(4, n); ++k) {
            const u = gallery.playlist[(gallery.cursor + k) % n];
            const known = gallery.aspectBook[String(u)];
            const err = Math.abs(others + (known !== undefined ? known : 1.5) - ideal);
            if (err < bestErr) {
                bestErr = err;
                bestK = k;
            }
        }
        if (bestK === 0) {
            gallery.frontLosses = 0;
        } else if (++gallery.frontLosses >= 3) {
            gallery.frontLosses = 0;
            bestK = 0;
        }
        if (bestK > 0) {
            const list = gallery.playlist.slice();
            const from = (gallery.cursor + bestK) % n;
            const to = gallery.cursor % n;
            const w = list[from];
            list[from] = list[to];
            list[to] = w;
            gallery.playlist = list;
        }
        const pick = gallery.takeNext();
        gallery.scoutAhead();
        return pick;
    }

    // --- photo of the day ---------------------------------------------------

    function dayNumber(): int {
        const now = new Date();
        return now.getFullYear() * 372 + now.getMonth() * 31 + now.getDate();
    }

    /** Which photo a slot shows today. Pure arithmetic over the sorted
        library, so every screen and every restart lands on the same one. */
    function dailyUrl(slot: int): url {
        const n = gallery.playlist.length;
        if (n === 0) {
            return "";
        }
        return gallery.playlist[(gallery.dayNumber() + slot) % n];
    }

    property int shownDay: 0

    function fill(slot: int): void {
        if (slot >= gallery.activeSlots) {
            return;
        }
        const target = slot === 0 ? card0 : (slot === 1 ? card1 : card2);
        if (gallery.daily) {
            gallery.shownDay = gallery.dayNumber();
            target.imageSource = gallery.dailyUrl(slot);
        } else {
            target.imageSource = gallery.takeBest(slot);
        }
    }

    onDailyChanged: {
        if (gallery.library.length > 0) {
            gallery.rebuild();
        }
    }

    // Sleeping through midnight must not stick yesterday's photo: whenever
    // the wall comes back to life on a new day, refill.
    onLiveChanged: {
        if (gallery.live && gallery.daily && gallery.shownDay !== gallery.dayNumber()
                && gallery.library.length > 0) {
            gallery.rebuild();
        }
    }

    // Realigned to the coming midnight on every firing, same trick as the
    // clock's minute tick.
    Timer {
        id: midnight
        running: gallery.daily && gallery.live && gallery.visible
        repeat: true
        interval: gallery.msToMidnight()
        onTriggered: {
            gallery.rebuild();
            midnight.interval = gallery.msToMidnight();
        }
    }

    function msToMidnight(): real {
        const now = new Date();
        const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
        return Math.max(1000, next - now);
    }

    // One slot at a time, so the wall never blinks all at once. Each card
    // still sits for the full interval; the changes are just interleaved.
    Timer {
        running: gallery.live && gallery.visible && !gallery.daily
            && gallery.playlist.length > gallery.activeSlots
        repeat: true
        interval: Math.max(5, gallery.interval / gallery.activeSlots) * 1000
        onTriggered: {
            gallery.skipBudget = gallery.playlist.length;
            gallery.fill(gallery.turn);
            gallery.turn = (gallery.turn + 1) % gallery.activeSlots;
        }
    }

    onActiveSlotsChanged: {
        gallery.skipBudget = gallery.playlist.length;
        for (let s = 0; s < 3; ++s) {
            gallery.fill(s);
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
            autoTransform: true
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
        id: cardRow
        objectName: "cardRow"
        anchors.centerIn: parent
        spacing: gallery.gap

        // OLED care. A fitted photo row is a bright static shape on a dark
        // field — worst case for burn-in — so the whole row wanders a
        // Lissajous of a few pixels over minutes. Unrounded on purpose: a
        // photo resampled half a texel over is indistinguishable, while a
        // whole-pixel step is a visible twitch.
        property real wx: 0
        property real wy: 0
        transform: Translate {
            x: cardRow.wx
            y: cardRow.wy
        }

        SequentialAnimation {
            running: true
            paused: !(gallery.live && gallery.burnInGuard && gallery.framed)
            loops: Animation.Infinite
            NumberAnimation { target: cardRow; property: "wx"; from: 0; to: 6; duration: 65000; easing.type: Easing.InOutSine }
            NumberAnimation { target: cardRow; property: "wx"; from: 6; to: -6; duration: 130000; easing.type: Easing.InOutSine }
            NumberAnimation { target: cardRow; property: "wx"; from: -6; to: 0; duration: 65000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation {
            running: true
            paused: !(gallery.live && gallery.burnInGuard && gallery.framed)
            loops: Animation.Infinite
            NumberAnimation { target: cardRow; property: "wy"; from: 0; to: -4; duration: 82000; easing.type: Easing.InOutSine }
            NumberAnimation { target: cardRow; property: "wy"; from: -4; to: 4; duration: 164000; easing.type: Easing.InOutSine }
            NumberAnimation { target: cardRow; property: "wy"; from: 4; to: 0; duration: 82000; easing.type: Easing.InOutSine }
        }

        /*
            A new photo brings a new aspect, and with it a new width for its
            card and new positions for its neighbours. Snapping there reads
            as the whole wall flinching, so geometry eases instead — the Row
            re-lays continuously while the widths glide, and the reflow
            rides the same beat as the crossfade. Disabled with the rest of
            the motion under reduced motion.
        */
        component EasedCard: GalleryCard {
            Behavior on width {
                enabled: gallery.live
                NumberAnimation { duration: 700; easing.type: Easing.InOutCubic }
            }
            Behavior on height {
                enabled: gallery.live
                NumberAnimation { duration: 700; easing.type: Easing.InOutCubic }
            }
        }

        EasedCard {
            id: card0
            visible: true
            width: gallery.framed ? gallery.cardH * aspect : gallery.width
            height: gallery.framed ? gallery.cardH : gallery.height
            fitMode: gallery.fitMode
            // A full-bleed photo has no edges to light and nothing behind
            // it to glow; the frame belongs to cards floating on the nebula.
            frameStyle: gallery.framed ? gallery.frameStyle : 0
            frameRadius: gallery.frameRadius
            live: gallery.live
            caption: gallery.captions && gallery.framed
            onSourceFailed: gallery.skipFailed(0)
        }

        EasedCard {
            id: card1
            visible: gallery.activeSlots > 1
            width: gallery.cardH * aspect
            height: gallery.cardH
            fitMode: gallery.fitMode
            frameStyle: gallery.framed ? gallery.frameStyle : 0
            frameRadius: gallery.frameRadius
            live: gallery.live
            caption: gallery.captions && gallery.framed
            onSourceFailed: gallery.skipFailed(1)
        }

        EasedCard {
            id: card2
            visible: gallery.activeSlots > 2
            width: gallery.cardH * aspect
            height: gallery.cardH
            fitMode: gallery.fitMode
            frameStyle: gallery.framed ? gallery.frameStyle : 0
            frameRadius: gallery.frameRadius
            live: gallery.live
            caption: gallery.captions && gallery.framed
            onSourceFailed: gallery.skipFailed(2)
        }
    }
}
