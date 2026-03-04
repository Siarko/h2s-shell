import QtQuick
import QtQuick.Layouts
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
    property var visualizerBars: []
    property real _ambientPhase: 0
    property string _cavaConfig: Qt.resolvedUrl("../scripts/cava.ini").toString().replace("file://", "")

    // Real audio data from cava
    Process {
        id: cava
        command: ["cava", "-p", root._cavaConfig]
        running: Music.hasPlayer
        stdout: SplitParser {
            onRead: line => {
                var vals = line.split(";").filter(s => s !== "").map(s => parseInt(s) / 100.0);
                if (vals.length > 0) {
                    root.useCava = true;
                    root.visualizerBars = vals;
                    waveCanvas.requestPaint();
                }
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
            var bars = [];
            for (var i = 0; i < 48; i++) {
                bars.push(
                    0.3 + 0.25 * Math.sin(root._ambientPhase + i * 0.25)
                        + 0.12 * Math.sin(root._ambientPhase * 2.3 + i * 0.6)
                );
            }
            root.visualizerBars = bars;
            waveCanvas.requestPaint();
        }
    }

    // Decay bars to flat line when paused
    Timer {
        interval: 100
        running: Music.hasPlayer && !Music.playing
        repeat: true
        onTriggered: {
            var decayed = root.visualizerBars.map(v => Math.max(0, v - 0.05));
            root.visualizerBars = decayed;
            waveCanvas.requestPaint();
        }
    }

    Column {
        id: col
        width: parent.implicitWidth
        spacing: 8

        // Player switcher tabs — hidden when 0 or 1 player
        Row {
            width: parent.width
            spacing: 4
            visible: Music.players.values.length > 1

            Repeater {
                model: Music.players

                delegate: Rectangle {
                    required property MprisPlayer modelData
                    width: tabLabel.implicitWidth + 16
                    height: 24
                    radius: 4
                    color: modelData === Music.activePlayer ? Theme.sliderAccent : tabArea.containsMouse ? Theme.buttonHover : "transparent"

                    Text {
                        id: tabLabel
                        anchors.centerIn: parent
                        text: modelData.identity || modelData.desktopEntry || "Player"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: modelData === Music.activePlayer ? Theme.textPrimary : Theme.textSecondary
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: tabArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Music.selectPlayer(modelData)
                    }
                }
            }
        }

        // Album art
        Item {
            width: parent.width
            height: Music.artUrl ? 120 : 0
            visible: Music.artUrl !== ""

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 120
                radius: 50
                clip: true

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

        // Waveform visualizer
        Canvas {
            id: waveCanvas
            width: parent.width
            height: 36
            visible: Music.hasPlayer

            onPaint: {
                var ctx = getContext("2d");
                var bars = root.visualizerBars;
                var w = width, h = height;
                ctx.clearRect(0, 0, w, h);
                if (bars.length < 2) return;

                var cx = w / (bars.length - 1);
                var amp = h / 2 * 0.85;
                var c = Theme.sliderAccent;

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

                ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.18);
                ctx.fill();
                ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.6);
                ctx.lineWidth = 1.5;
                ctx.stroke();
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
                font.pixelSize: 14
                font.bold: true
                color: Theme.textPrimary
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: Music.artist
                font.family: Theme.fontFamily
                font.pixelSize: 12
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
                font.pixelSize: 24
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
                font.pixelSize: 32
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
                font.pixelSize: 24
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
    }
}
