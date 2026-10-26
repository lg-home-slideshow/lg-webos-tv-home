// main.qml - TV Home, native: an Apple-TV-style Home for an LG webOS 10 TV,
// drawn by Qt Quick on the TV's graphics chip (the web version in ui/ goes
// through the browser engine and managed ~54 fps; this one runs as a QML app).
//
// Mounted over LG's Home under its id by tv-home.sh. Data and actions come
// from server.js on this TV (http://127.0.0.1:8650): the apps and inputs with
// their icons, launching, uninstalling, the dock, hidden apps, the photos.
import QtQuick 2.12
import QtGraphicalEffects 1.0
import Eos.Window 0.1

WebOSWindow {
    id: win
    width: 1920
    height: 1080
    windowType: "_WEBOS_WINDOW_TYPE_CARD"
    appId: "com.webos.app.home"
    title: "Home"
    visible: true
    color: "black"
    keyMask: WebOSWindow.KeyMaskDefault | WebOSWindow.KeyMaskBack

    readonly property string server: "http://127.0.0.1:8650"
    readonly property int tileW: 224
    readonly property int tileH: 134
    readonly property int gapW: 44
    readonly property int dockSpace: 1920 - 2 * 110 - 92
    readonly property int cols: 7
    readonly property int holdMs: 650

    // settings and state, from server.js
    property var config: ({ name: "", locale: "en-GB", hour24: true, photoSeconds: 30, dockSize: 6, dockMax: 12 })
    property var tiles: []
    property var order: []
    property var dockSaved: null
    property var hiddenKeys: []
    property var photos: []

    // what is shown, worked out from the state
    property var appsList: []
    property var inputsList: []
    property var hiddenList: []
    property var dockList: []

    property string area: "dock"          // dock | drawer | photo (Up: only the photos)
    property int dockIndex: 0
    property int drawerIndex: 0
    property bool lifted: false
    property var menuOptions: null        // [[label, function, danger]]
    property int menuIndex: 0
    property var menuTile: null
    property string menuTitle: ""
    property string menuSub: ""

    FontLoader { id: fontLight; source: "file:///usr/share/fonts/LG_Smart_UI-Light.ttf" }
    FontLoader { id: fontRegular; source: "file:///usr/share/fonts/LG_Smart_UI-Regular.ttf" }
    FontLoader { id: fontBold; source: "file:///usr/share/fonts/LG_Smart_UI-Bold.ttf" }
    FontLoader { id: fontSlim; source: "file:///usr/share/fonts/LG_SlimNumber-Light.ttf" }

    // ---- server ----------------------------------------------------------------------
    function api(method, path, data, cb) {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            var r = null;
            try { r = JSON.parse(x.responseText); } catch (e) {}
            if (cb) cb(x.status >= 200 && x.status < 300 ? r : null);
        };
        x.open(method, server + path);
        x.setRequestHeader("Content-Type", "application/json");
        x.send(data ? JSON.stringify(data) : null);
    }
    function report(msg) { api("POST", "/api/log", { msg: "qml: " + msg }, null); }

    Timer { id: loadRetry; interval: 2000; property var cb: null; onTriggered: load(cb) }
    function load(cb) {
        api("GET", "/api/state", null, function (s) {
            // no answer (at boot the server can start after us): again shortly
            if (!s) { loadRetry.cb = cb; loadRetry.start(); return; }
            // a new object, so the bindings that read config see the change
            var c = {}, k;
            for (k in config) c[k] = config[k];
            for (k in s.config) c[k] = s.config[k];
            config = c;
            tiles = s.tiles || [];
            order = s.order || [];
            dockSaved = s.dock && s.dock.length ? s.dock : null;
            hiddenKeys = s.hidden || [];
            if (s.photos && s.photos.length) photos = s.photos;
            rebuild();
            if (cb) cb();
        });
    }

    function save() {
        dockSaved = dockKeys();
        api("POST", "/api/order", { order: order, dock: dockSaved, hidden: hiddenKeys }, null);
    }

    // ---- lists ---------------------------------------------------------------------------
    function byKey(k) { for (var i = 0; i < tiles.length; i++) if (tiles[i].key === k) return tiles[i]; return null; }
    function isHidden(t) { return hiddenKeys.indexOf(t.key) !== -1; }
    function sortedApps() {
        var list = tiles.filter(function (t) { return t.kind === "app" && !isHidden(t); });
        return list.map(function (t, i) { var r = order.indexOf(t.key); return { t: t, r: r === -1 ? 1000 + i : r }; })
                   .sort(function (a, b) { return a.r - b.r; }).map(function (x) { return x.t; });
    }
    function dockKeys() {
        var keys = dockSaved && dockSaved.length ? dockSaved
                 : sortedApps().slice(0, config.dockSize).map(function (t) { return t.key; });
        return keys.filter(function (k) { var t = byKey(k); return t && !isHidden(t); });
    }
    function rebuild() {
        appsList = sortedApps();
        inputsList = tiles.filter(function (t) { return t.kind === "input" && !isHidden(t); });
        hiddenList = tiles.filter(isHidden);
        dockList = dockKeys().map(byKey);
        dockIndex = Math.max(0, Math.min(dockIndex, dockList.length - 1));
        drawerIndex = Math.max(0, Math.min(drawerIndex, drawerAll().length - 1));
    }
    function drawerAll() { return appsList.concat(inputsList).concat(hiddenList); }
    function current() { return area === "dock" ? dockList[dockIndex] : drawerAll()[drawerIndex]; }
    function inDock(t) { return dockKeys().indexOf(t.key) !== -1; }
    function tileLabel(t) { return t.kind === "input" && t.sub ? t.name + " · " + t.sub : t.name; }

    // the dock's tiles get narrower when it holds more than fit at full size
    property real dockTileW: Math.min(tileW, Math.floor((dockSpace - (Math.max(dockList.length, 1) - 1) * gapW) / Math.max(dockList.length, 1)))
    property real dockScale: dockTileW / tileW

    // ---- actions ---------------------------------------------------------------------------
    function open() {
        var t = current();
        if (!t) return;
        toast((t.kind === "input" ? "Switching to " : "Opening ") + t.name, "");
        api("POST", "/api/launch", { id: t.id, params: t.params || null }, function (r) {
            if (!r || r.returnValue === false) toast("Could not open " + t.name, r && r.errorText ? r.errorText : "no answer from the TV");
        });
    }
    function openDrawer() { area = "drawer"; drawerIndex = Math.min(dockIndex, cols - 1, drawerAll().length - 1); }
    function closeDrawer() { area = "dock"; }

    // All apps: one list over three sections of rows of `cols` tiles
    function layout() {
        var out = [], row = 0;
        [appsList, inputsList, hiddenList].forEach(function (list) {
            if (!list.length) return;
            for (var i = 0; i < list.length; i++) out.push({ row: row + Math.floor(i / cols), col: i % cols });
            row += Math.ceil(list.length / cols);
        });
        return out;
    }
    function drawerMove(key) {
        var lay = layout(), here = lay[drawerIndex];
        if (!here) return;
        if (key === Qt.Key_Left || key === Qt.Key_Right) {
            var j = drawerIndex + (key === Qt.Key_Left ? -1 : 1);
            if (lay[j] && lay[j].row === here.row) drawerIndex = j;
            return;
        }
        var row = here.row + (key === Qt.Key_Down ? 1 : -1);
        if (row < 0) { closeDrawer(); return; }
        var best = -1;
        for (var i = 0; i < lay.length; i++)
            if (lay[i].row === row && (best === -1 || Math.abs(lay[i].col - here.col) < Math.abs(lay[best].col - here.col))) best = i;
        if (best !== -1) drawerIndex = best;
    }

    function liftAt(i) { area = "dock"; dockIndex = i; lifted = true; }
    function drop() { lifted = false; save(); }
    function moveLifted(dir) {
        var keys = dockKeys(), j = dockIndex + dir;
        if (j < 0 || j >= keys.length) return;
        var tmp = keys[dockIndex]; keys[dockIndex] = keys[j]; keys[j] = tmp;
        dockSaved = keys; rebuild(); dockIndex = j;
    }

    function options() {
        var t = current();
        if (!t) return;
        var list = [];
        if (isHidden(t)) {
            list.push(["Show again", function () { hiddenKeys = hiddenKeys.filter(function (k) { return k !== t.key; }); save(); rebuild(); toast(t.name + " is back", ""); }]);
        } else {
            if (inDock(t)) {
                list.push(["Move", function () { liftAt(dockKeys().indexOf(t.key)); toast("Moving " + t.name, "left / right, then OK"); }]);
                if (dockKeys().length > 1) list.push(["Remove from dock", function () {
                    dockSaved = dockKeys().filter(function (k) { return k !== t.key; }); save(); rebuild();
                    toast(t.name + " is out of the dock", "it stays in All apps"); }]);
            } else {
                list.push(["Add to dock", function () {
                    var keys = dockKeys();
                    if (keys.length >= config.dockMax) { toast("The dock is full", "remove an app from it first"); return; }
                    keys.push(t.key); dockSaved = keys; save(); rebuild(); liftAt(keys.length - 1);
                    toast(t.name + " is in the dock", "left / right to place it, then OK"); }]);
            }
            list.push(["Hide", function () {
                if (dockKeys().length === 1 && inDock(t)) { toast("The dock needs one app", "add another first"); return; }
                dockSaved = dockKeys();
                var h = hiddenKeys.slice(); h.push(t.key); hiddenKeys = h; save(); rebuild();
                toast(t.name + " is hidden", "All apps, at the end: hold OK to show it again"); }]);
            if (t.removable) list.push(["Uninstall…", function () { confirmUninstall(t); }, true]);
        }
        list.push(["Cancel", function () {}]);
        showMenu(t, t.name, t.kind === "input" ? (t.sub || "Input") : (inDock(t) ? "In the dock" : "In All apps"), list, 0);
    }
    function confirmUninstall(t) {
        showMenu(t, "Uninstall " + t.name + "?",
                 "It is deleted from the TV. If the LG Content Store is blocked on this TV, it may not be possible to install it again.",
                 [["Uninstall", function () { uninstall(t); }, true], ["Cancel", function () {}]], 1);
    }
    function uninstall(t) {
        toast("Uninstalling " + t.name, "");
        api("POST", "/api/uninstall", { id: t.id }, function (r) {
            if (!r || r.returnValue === false) { toast("Could not uninstall " + t.name, r && r.errorText ? r.errorText : "no answer from the TV"); return; }
            toast(t.name + " is uninstalled", "");
            reloadLater.start();
        });
    }
    function showMenu(t, title, sub, list, index) {
        menuTile = t; menuTitle = title; menuSub = sub; menuIndex = index; menuOptions = list;
    }
    function choose() {
        var o = menuOptions[menuIndex];
        menuOptions = null;
        o[1]();
    }

    Timer { id: reloadLater; interval: 2500; onTriggered: load(null) }

    // ---- toast -------------------------------------------------------------------------------
    property string toastText: ""
    property string toastSub: ""
    function toast(text, sub) { toastText = text; toastSub = sub || ""; toastBox.shown = true; toastTimer.restart(); }
    Timer { id: toastTimer; interval: 3000; onTriggered: toastBox.shown = false }

    // ---- background photos: cross-fading, slowly drifting ------------------------------------
    property int photoIndex: -1
    property bool frontA: true
    function nextPhoto() {
        if (!photos.length) return;
        photoIndex = photoIndex === -1 ? Math.floor(Math.random() * photos.length) : (photoIndex + 1) % photos.length;
        var next = frontA ? bgB : bgA;
        next.source = server + photos[photoIndex];
    }
    Timer { id: photoTimer; interval: Math.max(config.photoSeconds, 5) * 1000; repeat: true; running: photos.length > 1; onTriggered: nextPhoto() }

    Item {
        id: bgRoot
        anchors.fill: parent

        Repeater {
            model: 2
            Image {
                id: bgImg
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: 1920
                property bool front: index === 0 ? frontA : !frontA
                opacity: front ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 1800; easing.type: Easing.InOutQuad } }
                onStatusChanged: if (status === Image.Ready && !front) { frontA = index === 0; drift.restart(); }
                // held while All apps covers it (it is blurred out anyway)
                NumberAnimation on scale { id: drift; from: 1.0; to: 1.08; duration: 40000; running: false; paused: running && area === "drawer" }
                Component.onCompleted: { if (index === 0) bgA = bgImg; else bgB = bgImg; }
            }
        }
    }
    property Image bgA: null
    property Image bgB: null

    // darkening for the text and the dock
    LinearGradient {
        anchors.fill: parent
        opacity: area === "photo" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 600 } }
        start: Qt.point(0, 0); end: Qt.point(0, 1080)
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#40000000" }
            GradientStop { position: 0.3; color: "#00000000" }
            GradientStop { position: 0.52; color: "#00000000" }
            GradientStop { position: 1.0; color: "#99000000" }
        }
    }
    RadialGradient {
        anchors.fill: parent
        opacity: area === "photo" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 600 } }
        horizontalOffset: -960; verticalOffset: -540
        horizontalRadius: 1350; verticalRadius: 650
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#73000000" }
            GradientStop { position: 1.0; color: "#00000000" }
        }
    }

    // ---- clock, greeting, date ----------------------------------------------------------------
    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: true; onTriggered: now = new Date() }
    function greeting() {
        var h = now.getHours();
        var part = h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : h < 23 ? "Good evening" : "Good night";
        return config.name ? part + ", " + config.name : part;
    }

    Column {
        id: header
        x: 112; y: 84
        opacity: area === "dock" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
        Text {
            text: Qt.formatTime(now, config.hour24 ? "HH:mm" : "h:mm")
            color: "white"
            font.family: fontSlim.status === FontLoader.Ready ? fontSlim.name : fontLight.name
            font.pixelSize: 190
            style: Text.Raised; styleColor: "#33000000"
        }
        Text {
            topPadding: 12
            text: greeting()
            color: "white"
            font.family: fontBold.name
            font.pixelSize: 46
            style: Text.Raised; styleColor: "#40000000"
        }
        Text {
            topPadding: 6
            text: now.toLocaleDateString(Qt.locale(config.locale.replace("-", "_")), "dddd, d MMMM")
            color: "#bdffffff"
            font.family: fontRegular.name
            font.pixelSize: 30
        }
    }

    // ---- dock, on frosted glass ------------------------------------------------------------------
    Item {
        id: dockArea
        width: dockRow.width + 92
        // just the tiles on the glass; the focused tile's name goes under it
        property int pad: 30
        height: Math.round(tileH * dockScale) + 2 * pad
        anchors.horizontalCenter: parent.horizontalCenter
        y: 1080 - 136 - height +(area === "drawer" ? 70 : area === "photo" ? 140 : 0)
        opacity: area === "dock" ? 1 : 0
        enabled: area === "dock"
        Behavior on y { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 400 } }

        // the background behind the dock, blurred
        ShaderEffectSource {
            id: dockBg
            anchors.fill: parent
            sourceItem: bgRoot
            sourceRect: Qt.rect(dockArea.x, dockArea.y, dockArea.width, dockArea.height)
            visible: false
        }
        FastBlur { id: dockBlur; anchors.fill: parent; source: dockBg; radius: 64; visible: false }
        Rectangle { id: dockMask; anchors.fill: parent; radius: 48; visible: false }
        OpacityMask { anchors.fill: parent; source: dockBlur; maskSource: dockMask }
        Rectangle {
            anchors.fill: parent
            radius: 48
            color: "#26ffffff"
            border.color: "#3dffffff"
            border.width: 1
        }

        Row {
            id: dockRow
            x: 46; y: dockArea.pad
            spacing: Math.round(gapW * Math.max(dockScale, 0.7))
            Repeater {
                model: dockList
                Tile {
                    item: modelData
                    server: win.server
                    width: dockTileW
                    height: Math.round(tileH * dockScale)
                    radius: Math.round(26 * Math.max(dockScale, 0.6))
                    labelGap: dockArea.pad + 14
                    fontFamily: fontRegular.name
                    label: tileLabel(modelData)
                    focused: area === "dock" && index === dockIndex && !menuOptions
                    lifted: lifted && index === dockIndex
                    onHovered: if (!lifted && !menuOptions) { area = "dock"; dockIndex = index; }
                    onClicked: { if (lifted) { drop(); return; } area = "dock"; dockIndex = index; open(); }
                    onHeld: { area = "dock"; dockIndex = index; options(); }
                }
            }
        }
    }
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: dockArea.y + dockArea.height + 62   // below the focused tile's name
        spacing: 10
        opacity: area === "dock" ? 0.8 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
        // a chevron, drawn: the TV's fonts have no arrow glyph
        Item {
            width: 22; height: 22
            anchors.verticalCenter: parent.verticalCenter
            Rectangle { width: 13; height: 3; radius: 1.5; color: "white"; x: 1; y: 8; rotation: 40 }
            Rectangle { width: 13; height: 3; radius: 1.5; color: "white"; x: 9; y: 8; rotation: -40 }
        }
        Text { text: "All apps"; color: "white"; font.pixelSize: 22; font.family: fontBold.name }
    }

    // ---- All apps -------------------------------------------------------------------------------
    Item {
        id: drawer
        width: 1920; height: 1080
        y: area === "drawer" ? 0 : 1080
        Behavior on y { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        visible: y < 1080

        ShaderEffectSource { id: drawerBg; anchors.fill: parent; sourceItem: bgRoot; visible: false; live: area === "drawer" }
        FastBlur { anchors.fill: parent; source: drawerBg; radius: 80 }
        Rectangle { anchors.fill: parent; color: "#8c0c0c10" }

        Flickable {
            id: drawerFlick
            x: 112; y: 96
            width: 1920 - 224; height: 1080 - 96
            contentHeight: drawerCol.height + 120
            interactive: false
            clip: false
            Behavior on contentY { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

            Column {
                id: drawerCol
                spacing: 0
                Repeater {
                    model: [["Apps", appsList, 0], ["Inputs", inputsList, appsList.length], ["Hidden", hiddenList, appsList.length + inputsList.length]]
                    Column {
                        id: sec
                        visible: modelData[1].length > 0
                        spacing: 34
                        bottomPadding: 84
                        Text { text: modelData[0]; color: "#bdffffff"; font.pixelSize: 30; font.family: fontBold.name }
                        Grid {
                            columns: cols
                            columnSpacing: 42
                            rowSpacing: 70
                            Repeater {
                                model: modelData[1]
                                Tile {
                                    id: dt
                                    property int flat: sec.offset + index
                                    item: modelData
                                    server: win.server
                                    width: 204; height: 122; radius: 22
                                    fontFamily: fontRegular.name
                                    label: tileLabel(modelData)
                                    dimmed: isHidden(modelData)
                                    focused: area === "drawer" && drawerIndex === flat && !menuOptions
                                    onFocusedChanged: if (focused) {
                                        var p = dt.mapToItem(drawerCol, 0, 0);
                                        drawerFlick.contentY = Math.max(0, p.y + dt.height + 90 - drawerFlick.height);
                                    }
                                    onHovered: if (!menuOptions) { area = "drawer"; drawerIndex = flat; }
                                    onClicked: { area = "drawer"; drawerIndex = flat; open(); }
                                    onHeld: { area = "drawer"; drawerIndex = flat; options(); }
                                }
                            }
                        }
                        property int offset: modelData[2]
                    }
                }
            }
        }
    }

    // ---- options menu ------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#59000000"
        opacity: menuOptions ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        MouseArea { anchors.fill: parent; onClicked: menuOptions = null }

        Rectangle {
            id: menuBox
            anchors.centerIn: parent
            width: 640
            height: menuCol.height + 68
            radius: 34
            color: "#f01c1c22"
            border.color: "#3dffffff"
            scale: menuOptions ? 1 : 0.94
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            Column {
                id: menuCol
                x: 34; y: 34
                width: parent.width - 68
                spacing: 6
                Row {
                    spacing: 26
                    bottomPadding: 20
                    Tile { item: menuTile; server: win.server; width: 150; height: 90; radius: 18; fontFamily: fontRegular.name; label: "" }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 400
                        Text { text: menuTitle; color: "white"; font.pixelSize: 34; font.family: fontBold.name; width: parent.width; elide: Text.ElideRight }
                        Text { text: menuSub; color: "#bdffffff"; font.pixelSize: 21; font.family: fontRegular.name; width: parent.width; wrapMode: Text.WordWrap }
                    }
                }
                Repeater {
                    model: menuOptions || []
                    Rectangle {
                        width: menuCol.width
                        height: 64
                        radius: 18
                        property bool on: index === menuIndex
                        property bool danger: modelData[2] === true
                        color: on ? (danger ? "#ff453a" : "white") : "transparent"
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 26
                            text: modelData[0]
                            color: parent.on ? (parent.danger ? "white" : "#111") : (parent.danger ? "#ff6b6b" : "white")
                            font.pixelSize: 28
                            font.family: fontBold.name
                        }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: menuIndex = index; onClicked: { menuIndex = index; choose(); } }
                    }
                }
            }
        }
    }

    // ---- toast -------------------------------------------------------------------------------
    Rectangle {
        id: toastBox
        property bool shown: false
        anchors.horizontalCenter: parent.horizontalCenter
        y: shown ? 54 : 24
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
        Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        width: toastRow.width + 68
        height: 66
        radius: 33
        color: "#e6141418"
        border.color: "#3dffffff"
        Row {
            id: toastRow
            anchors.centerIn: parent
            spacing: 18
            Text { text: toastText; color: "white"; font.pixelSize: 26; font.family: fontBold.name; anchors.verticalCenter: parent.verticalCenter }
            Text { text: toastSub; visible: toastSub !== ""; color: "#bdffffff"; font.pixelSize: 20; font.family: fontRegular.name; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // ---- remote ---------------------------------------------------------------------------------
    // OK opens on release; held for holdMs it opens the options. An OK that
    // chose something on its press (menu entry, dropping a tile) does not also
    // open on its release.
    // The TV can repeat a held OK as new press + release pairs, not marked as
    // repeats: so a release only counts when no press follows within upGrace.
    property bool held: false
    property bool swallowUp: false
    property bool okDown: false
    readonly property int upGrace: 140
    Timer { id: holdTimer; interval: holdMs; onTriggered: { held = true; options(); } }
    Timer { id: upTimer; interval: upGrace; onTriggered: okUp() }

    function okUp() {
        okDown = false;
        holdTimer.stop();
        if (swallowUp) { swallowUp = false; held = false; return; }
        if (!held && !menuOptions && !lifted) open();
        held = false;
    }


    function isOk(k) { return k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Select; }
    function isBack(k) { return k === Qt.Key_Escape || k === Qt.Key_Back || k === Qt.Key_Backspace || k === 0x1200003 /* the remote's Back on webOS 10 */ || k === 461; }
    function isArrow(k) { return k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down; }

    // only the photos: a click with the Magic Remote brings the dock back
    MouseArea {
        anchors.fill: parent
        enabled: area === "photo"
        onClicked: area = "dock"
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: {
            var k = event.key;
            // 0x1200201/2: the Magic Remote's pointer shown/hidden
            if (!isOk(k) && !isBack(k) && !isArrow(k)) { if (k !== 0x1200201 && k !== 0x1200202) report("unhandled key " + k + " (0x" + k.toString(16) + ")"); return; }
            event.accepted = true;
            if (isOk(k)) {
                // a repeat of an OK still held: keep the hold going
                if (event.isAutoRepeat || okDown || upTimer.running) { upTimer.stop(); okDown = true; return; }
                okDown = true;
            }

            // only the photos: Right the next one; Down, OK or Back the dock again
            if (area === "photo") {
                if (k === Qt.Key_Right) nextPhoto();
                else if (k === Qt.Key_Down || isOk(k) || isBack(k)) { area = "dock"; swallowUp = isOk(k); }
                return;
            }

            if (menuOptions) {
                if (k === Qt.Key_Up && menuIndex > 0) menuIndex--;
                if (k === Qt.Key_Down && menuIndex < menuOptions.length - 1) menuIndex++;
                if (isOk(k)) { swallowUp = true; choose(); }
                if (isBack(k)) menuOptions = null;
                return;
            }
            if (lifted) {
                if (k === Qt.Key_Left) moveLifted(-1);
                if (k === Qt.Key_Right) moveLifted(1);
                if (isOk(k) || isBack(k)) { swallowUp = isOk(k); drop(); }
                return;
            }
            if (isOk(k)) { held = false; holdTimer.restart(); return; }
            if (area === "dock") {
                if (k === Qt.Key_Left && dockIndex > 0) dockIndex--;
                if (k === Qt.Key_Right && dockIndex < dockList.length - 1) dockIndex++;
                if (k === Qt.Key_Down) openDrawer();
                if (k === Qt.Key_Up) area = "photo";
                return;
            }
            if (isArrow(k)) drawerMove(k);
            if (isBack(k)) closeDrawer();
        }
        Keys.onReleased: {
            if (!isOk(event.key)) return;
            event.accepted = true;
            if (event.isAutoRepeat) return;
            upTimer.restart();
        }
    }

    // ---- heartbeat (the watchdog's sign of life) and coming back to Home -----------------------
    Timer {
        interval: 5000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: api("POST", "/api/heartbeat", {}, function (r) {
            if (r && r.bench) bench();
            // new photos (Install-TVHome.ps1, Change photos): the new list, and the next photo from it
            if (r && r.remote && r.remote.reload) load(function () { photoIndex = -1; nextPhoto(); });
            if (r && r.remote && /^(dock|drawer|photo)$/.test(r.remote.area)) {   // a test from ssh
                if (r.remote.area === "drawer" && area !== "drawer") openDrawer(); else area = r.remote.area;
                if (typeof r.remote.index === "number") { if (area === "drawer") drawerIndex = r.remote.index; else dockIndex = r.remote.index; }
            }
        })
    }
    onActiveChanged: if (active) { keys.forceActiveFocus(); if (area === "photo") area = "dock"; if (!menuOptions && !lifted) load(null); nextPhoto(); }

    // ---- frame-rate measurement (POST /api/bench on server.js) --------------------------------
    property int benchFrames: 0
    property bool benching: false
    Connections { target: win; onFrameSwapped: if (benching) benchFrames++ }
    property var benchSteps: []
    Timer {
        id: benchTimer; interval: 400; repeat: true
        property int step: 0
        property real started: 0
        onTriggered: {
            var n = Math.min(Math.max(dockList.length - 1, 1), 4);
            if (step < n) { dockIndex++; }
            else if (step < 2 * n) { dockIndex--; }
            else if (step === 2 * n) openDrawer();
            else if (step === 2 * n + 1 || step === 2 * n + 2) drawerMove(Qt.Key_Right);
            else if (step === 2 * n + 3) closeDrawer();
            else if (step > 2 * n + 5) {
                stop(); benching = false;
                var secs = (Date.now() - started) / 1000;
                api("POST", "/api/bench/result", { mode: "qml", seconds: Math.round(secs * 10) / 10, fps: Math.round(benchFrames / secs), frames: benchFrames }, null);
            }
            step++;
        }
    }
    function bench() {
        if (menuOptions || lifted || area !== "dock") return;
        dockIndex = 0; benchFrames = 0; benching = true;
        benchTimer.step = 0; benchTimer.started = Date.now(); benchTimer.start();
    }

    Component.onCompleted: {
        // Back is the compositor's unless the window asks for it (it would
        // show LG's "exit app?"), as LG's own QML apps do; Home stays the system's.
        // (as LG's example QML app on this TV does)
        try { windowProperties._WEBOS_ACCESS_POLICY_KEYS_BACK = true; } catch (e) { report("back policy: " + e); }
        keys.forceActiveFocus();
        load(function () { nextPhoto(); });
    }
}
