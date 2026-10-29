import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Io
import qs.components
import qs.singletons
import QtQuick.Effects

Item {
    id: root
    implicitWidth: 320
    implicitHeight: col.implicitHeight

    property bool useCava: false
    property var leftBars: []
    property var rightBars: []
    property real _ambientPhase: 0
    // cava runs from a config generated from the shell's own scripts/cava.ini, with the
    // frame rate the active profile sets ("polling.visualizer.fps"); the template stays
    // the one place to edit the rest of cava's settings
    readonly property int _cavaFps: Profiles.value("polling.visualizer.fps") ?? 60
    readonly property bool _cavaWanted: Music.hasPlayer

    on_CavaFpsChanged: _restartCava()
    on_CavaWantedChanged: _restartCava()
    Component.onCompleted: _restartCava()

    // Writes the config and (re)starts cava if a player is there. A Process must not be
    // started by a declarative `running:` binding — see CLAUDE.md.
    function _restartCava() {
        cava.running = false;
        if (!_cavaWanted)
            return;
        const template = _cavaTemplate.text();
        _cavaGenerated.setText(template.replace(/^framerate\s*=.*$/m, "framerate = " + _cavaFps));
        Qt.callLater(() => cava.running = root._cavaWanted);
    }

    FileView {
        id: _cavaTemplate
        path: Qt.resolvedUrl("../scripts/cava.ini").toString().replace("file://", "")
        blockLoading: true
    }

    FileView {
        id: _cavaGenerated
        path: Quickshell.cachePath("cava.ini")
        blockWrites: true
        // Only ever written; it does not exist until the first write, and that is fine
        printErrors: false
    }

    function _requestAllPaint() {
        waveCanvas.requestPaint();
        leftCanvas.requestPaint();
        rightCanvas.requestPaint();
    }

    function drawWaveform(ctx, bars, w, h, vertical) {
        if (bars.length < 2)
            return;
        var c = Theme.sliderAccent;

        if (!vertical) {
            var cx = w / (bars.length - 1);
            var amp = h / 2 * 0.85;
            ctx.beginPath();
            ctx.moveTo(0, h / 2);
            for (var i = 0; i < bars.length - 1; i++) {
                var x0 = i * cx, x1 = (i + 1) * cx;
                var y0 = h / 2 - bars[i] * amp;
                var y1 = h / 2 - bars[i + 1] * amp;
                ctx.quadraticCurveTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
            }
            ctx.lineTo(w, h / 2);
            for (var j = bars.length - 2; j >= 0; j--) {
                var x0b = j * cx, x1b = (j + 1) * cx;
                var y0b = h / 2 + bars[j] * amp;
                var y1b = h / 2 + bars[j + 1] * amp;
                ctx.quadraticCurveTo(x1b, y1b, (x0b + x1b) / 2, (y0b + y1b) / 2);
            }
            ctx.closePath();
        } else {
            // axes swapped: center is vertical line at w/2, curves go left/right
            var cy = h / (bars.length - 1);
            var amp = w / 2 * 0.85;
            ctx.beginPath();
            ctx.moveTo(w / 2, 0);
            for (var i = 0; i < bars.length - 1; i++) {
                var y0 = i * cy, y1 = (i + 1) * cy;
                var x0 = w / 2 - bars[i] * amp;
                var x1 = w / 2 - bars[i + 1] * amp;
                ctx.quadraticCurveTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
            }
            ctx.lineTo(w / 2, h);
            for (var j = bars.length - 2; j >= 0; j--) {
                var y0b = j * cy, y1b = (j + 1) * cy;
                var x0b = w / 2 + bars[j] * amp;
                var x1b = w / 2 + bars[j + 1] * amp;
                ctx.quadraticCurveTo(x1b, y1b, (x0b + x1b) / 2, (y0b + y1b) / 2);
            }
            ctx.closePath();
        }

        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.18);
        ctx.fill();
        ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.6);
        ctx.lineWidth = 1.5;
        ctx.stroke();
    }

    // fromRight: left canvas bars anchor to right edge and grow left
    function drawBars(ctx, bars, w, h, vertical, fromRight) {
        if (bars.length === 0)
            return;
        var c = Theme.sliderAccent;
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.7);

        var n = bars.length;
        if (vertical) {
            var barH = (h - (n - 1) * 2) / n;
            for (var i = 0; i < n; i++) {
                var y = i * (barH + 2);
                var barLen = w * bars[i];
                if (fromRight) {
                    ctx.fillRect(w - barLen, y, barLen, barH);
                } else {
                    ctx.fillRect(0, y, barLen, barH);
                }
            }
        } else {
            var barW = (w - (n - 1) * 2) / n;
            for (var i = 0; i < n; i++) {
                var x = i * (barW + 2);
                var barH = h / 2 * bars[i];
                ctx.fillRect(x, h / 2, barW, barH);
                ctx.fillRect(x, h / 2, barW, -barH);
            }
        }
    }

    function drawDots(ctx, bars, w, h, vertical) {
        if (bars.length === 0)
            return;
        var c = Theme.sliderAccent;
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.9);

        var n = bars.length;
        var r = 2.5;
        if (!vertical) {
            var cx = w / (n > 1 ? n - 1 : 1);
            var amp = h / 2 * 0.85;
            for (var i = 0; i < n; i++) {
                var x = i * cx;
                var dy = bars[i] * amp;
                ctx.beginPath();
                ctx.arc(x, h / 2 - dy, r, 0, Math.PI * 2);
                ctx.fill();
                ctx.beginPath();
                ctx.arc(x, h / 2 + dy, r, 0, Math.PI * 2);
                ctx.fill();
            }
        } else {
            var cy = h / (n > 1 ? n - 1 : 1);
            var amp = w / 2 * 0.85;
            for (var i = 0; i < n; i++) {
                var y = i * cy;
                var dx = bars[i] * amp;
                ctx.beginPath();
                ctx.arc(w / 2 - dx, y, r, 0, Math.PI * 2);
                ctx.fill();
                ctx.beginPath();
                ctx.arc(w / 2 + dx, y, r, 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }

    // Real audio data from cava
    Process {
        id: cava
        command: ["cava", "-p", _cavaGenerated.path]
        stdout: SplitParser {
            onRead: line => {
                var vals = line.split(";").filter(s => s !== "").map(s => parseInt(s) / 100.0);
                const bars = vals.length;
                root.useCava = true;
                root.leftBars = vals.slice(0, bars / 2);
                root.rightBars = vals.slice(bars / 2);
                root._requestAllPaint();
            }
        }
    }

    // Ambient fallback when cava is unavailable
    Timer {
        interval: 33
        running: Music.playing && !root.useCava
        repeat: true
        onTriggered: {
            root._ambientPhase += 0.08;
            var left = [], right = [];
            for (var i = 0; i < 24; i++) {
                left.push(0.3 + 0.25 * Math.sin(root._ambientPhase + i * 0.25) + 0.12 * Math.sin(root._ambientPhase * 2.3 + i * 0.6));
                right.push(0.3 + 0.25 * Math.sin(root._ambientPhase + i * 0.25 + 0.8) + 0.12 * Math.sin(root._ambientPhase * 2.3 + i * 0.6 + 0.4));
            }
            root.leftBars = left;
            root.rightBars = right;
            root._requestAllPaint();
        }
    }

    // Decay bars to flat line when paused
    Timer {
        interval: 100
        running: Music.hasPlayer && !Music.playing
        repeat: true
        onTriggered: {
            root.leftBars = root.leftBars.map(v => Math.max(0, v - 0.05));
            root.rightBars = root.rightBars.map(v => Math.max(0, v - 0.05));
            root._requestAllPaint();
        }
    }

    // Repaint when style or layout setting changes
    Connections {
        target: Config.media
        function onVisualizerStyleChanged() {
            root._requestAllPaint();
        }
        function onVisualizerLayoutChanged() {
            root._requestAllPaint();
        }
    }

    // Left channel canvas — spans full popup height, bars grow from left edge inward
    Canvas {
        id: leftCanvas
        x: 0
        width: 100
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: Config.media.visualizerLayout === "vertical" && Music.hasPlayer && Config.media.visualizerStyle !== "none"
        onVisibleChanged: if (visible)
            requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var style = Config.media.visualizerStyle;
            if (style === "waveform")
                root.drawWaveform(ctx, root.leftBars, width, height, true);
            else if (style === "bars")
                root.drawBars(ctx, root.leftBars, width, height, true, false);
            else if (style === "dots")
                root.drawDots(ctx, root.leftBars, width, height, true);
        }
    }

    // Right channel canvas — spans full popup height, bars grow from right edge inward
    Canvas {
        id: rightCanvas
        x: 220
        width: 100
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: Config.media.visualizerLayout === "vertical" && Music.hasPlayer && Config.media.visualizerStyle !== "none"
        onVisibleChanged: if (visible)
            requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var style = Config.media.visualizerStyle;
            if (style === "waveform")
                root.drawWaveform(ctx, root.rightBars.reverse(), width, height, true);
            else if (style === "bars")
                root.drawBars(ctx, root.rightBars.reverse(), width, height, true, true);
            else if (style === "dots")
                root.drawDots(ctx, root.rightBars.reverse(), width, height, true);
        }
    }

    Column {
        id: col
        width: parent.implicitWidth
        spacing: 8

        // Player switcher list — hidden when 0 or 1 player
        Item {
            width: parent.width
            implicitHeight: playerList.implicitHeight
            visible: Music.players.values.length > 1

            Column {
                id: playerList
                width: parent.width
                spacing: 2

                Repeater {
                    // Wrapping the live model in ScriptModel makes the Repeater diff
                    // old vs. new values and only add/remove the changed delegates.
                    // Binding straight to Music.players.values (or any plain JS array)
                    // makes QQuickRepeater destroy and re-incubate every delegate on
                    // every change, which is what was crashing this app in
                    // QQuickRepeater::regenerate() -> QQmlIncubatorPrivate::incubate().
                    // Same pattern in BluetoothPanel.qml, AudioChannelRow.qml,
                    // TrayWidget.qml, NetworkPanel.qml.
                    model: ScriptModel {
                        values: Music.players.values
                    }

                    delegate: Text {
                        required property MprisPlayer modelData
                        width: parent.width
                        leftPadding: 8
                        text: "• " + (modelData.identity || modelData.desktopEntry || "Player")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        font.bold: modelData === Music.activePlayer
                        color: modelData === Music.activePlayer ? Theme.sliderAccent : Theme.textSecondary
                        elide: Text.ElideRight

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Music.selectPlayer(modelData)
                        }
                    }
                }
            }

            CustomMouseArea {
                anchors.fill: parent
                z: -1
                onScrollNotchY: direction => {
                    let players = Music.players.values;
                    let index = players.indexOf(Music.activePlayer);
                    let next = Math.max(0, Math.min(players.length - 1, index - direction));
                    Music.selectPlayer(players[next]);
                }
            }
        }

        // Album art row
        Item {
            width: parent.width
            height: 120
            // In vertical mode: show whenever there's a player (canvases need space even without art).
            // In horizontal mode: only show when art is available (original behavior).
            visible: Config.media.visualizerLayout === "vertical" ? Music.hasPlayer : Music.artUrl !== ""

            // Album art (centered, always 120×120)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 120
                radius: 50
                clip: true
                visible: Music.artUrl !== ""

                MultiEffect {
                    source: image
                    anchors.fill: image
                    maskEnabled: true
                    maskSource: mask
                    maskSpreadAtMin: 1
                    maskThresholdMin: 0.5
                }

                Image {
                    id: image
                    anchors.fill: parent
                    source: Music.artUrl
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                }

                Item {
                    id: mask
                    anchors.fill: image
                    layer.enabled: true
                    visible: false

                    Rectangle {
                        anchors.fill: parent
                        radius: 20
                    }
                }
            }
        }

        // Track info
        Column {
            width: parent.width
            spacing: 2

            Text {
                width: parent.width
                text: Music.hasPlayer ? (Music.title || "Unknown") : "No media"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
                color: Theme.textPrimary
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: Music.artist
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                visible: Music.artist !== ""
            }
        }

        // Seek bar
        SeekBar {
            width: parent.width
            position: Music.position
            duration: Music.length
            canSeek: Music.canSeek
            onSeeked: pos => Music.setPosition(pos)
            visible: Music.hasPlayer
        }

        // Transport controls
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 20
            visible: Music.hasPlayer

            // Previous
            Text {
                text: "󰒮"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLargeDisplay
                color: !Music.canPrev ? Theme.textDim : prevArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    id: prevArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Music.canPrev ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: Music.previous()
                }
            }

            // Play/Pause
            Text {
                text: Music.playing ? "󰏤" : "󰐊"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXXLargeDisplay
                color: playArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    id: playArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Music.togglePlay()
                }
            }

            // Next
            Text {
                text: "󰒭"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLargeDisplay
                color: !Music.canNext ? Theme.textDim : nextArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    id: nextArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Music.canNext ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: Music.next()
                }
            }
        }

        // Horizontal visualizer canvas
        Canvas {
            id: waveCanvas
            width: parent.width
            height: 36
            visible: Config.media.visualizerLayout === "horizontal" && Music.hasPlayer && Config.media.visualizerStyle !== "none"
            onVisibleChanged: if (visible)
                requestPaint()

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                const bars = [...root.leftBars, ...root.rightBars.reverse()];
                var style = Config.media.visualizerStyle;
                if (style === "waveform")
                    root.drawWaveform(ctx, bars, width, height, false);
                else if (style === "bars") {
                    root.drawBars(ctx, bars, width, height, false, false);
                } else if (style === "dots")
                    root.drawDots(ctx, bars, width, height, false, false);
            }
        }
    }
}
