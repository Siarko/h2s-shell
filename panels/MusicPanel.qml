import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import qs.components
import qs.singletons
import qs.panels.music
import QtQuick.Effects

// The music popup: players to pick from, the cover, the track, seeking, transport, and the
// visualiser (Visualizer's levels, drawn by VisualizerCanvas) beside or below them
Item {
    id: root
    implicitWidth: Theme.popupWidth("music", 320)
    implicitHeight: col.implicitHeight

    // Cava runs only while the panel is open (Visualizer)
    Component.onCompleted: Visualizer.addViewer()
    Component.onDestruction: Visualizer.removeViewer()

    // From the active profile
    readonly property string visualizerStyle: Profiles.value("media.visualizerStyle") ?? "waveform"
    readonly property string visualizerLayout: Profiles.value("media.visualizerLayout") ?? "horizontal"
    readonly property bool _showVisualizer: Music.hasPlayer && visualizerStyle !== "none"

    // Vertical layout: a channel down each side, spanning the panel's height, bars growing
    // inward from the edge, the two in the same order top to bottom. Cava sends the
    // channels in opposite orders (mirrored, for one strip), so the right is turned round.
    VisualizerCanvas {
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: 100
        visible: root.visualizerLayout === "vertical" && root._showVisualizer
        vertical: true
        style: root.visualizerStyle
        bars: Visualizer.leftBars
    }

    VisualizerCanvas {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 100
        visible: root.visualizerLayout === "vertical" && root._showVisualizer
        vertical: true
        fromRight: true
        style: root.visualizerStyle
        bars: Visualizer.rightBars.slice().reverse()
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
                    // ScriptModel, never the bare array — see "The Repeater crash" in
                    // docs/ARCHITECTURE.md
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
                        color: modelData === Music.activePlayer ? Theme.accent : Theme.textSecondary
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
            visible: root.visualizerLayout === "vertical" ? Music.hasPlayer : Music.artUrl !== ""

            // Album art (centered, always 120×120)
            Rectangle {
                id: _art
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 120
                // Only a frame: the cover's rounding comes from its mask below
                color: "transparent"
                clip: true
                visible: Music.artUrl !== ""
                // A new track's cover fades in once it has loaded
                opacity: image.status === Image.Ready ? 1 : 0
                Connections {
                    target: image
                    function onStatusChanged() {
                        if (image.status === Image.Ready)
                            _artFadeIn.restart();
                        else
                            _art.opacity = 0;
                    }
                }
                NumberAnimation {
                    id: _artFadeIn
                    target: _art
                    from: 0
                    property: "opacity"
                    to: 1
                    duration: Theme.duration("fade")
                    easing: Theme.curve("fade")
                }

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

        // Track info; a new track's title and artist fade in
        Column {
            id: _trackInfo
            width: parent.width
            spacing: 2

            Connections {
                target: Music
                function onTitleChanged() { _trackFadeIn.restart() }
            }
            NumberAnimation {
                id: _trackFadeIn
                target: _trackInfo
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.duration("fade")
                easing: Theme.curve("fade")
            }

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
                color: !Music.canPrev ? Theme.textDisabled : prevArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
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
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
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
                color: !Music.canNext ? Theme.textDisabled : nextArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
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

        // Horizontal layout: both channels in one strip, bass at both ends and treble
        // meeting in the middle — cava's own stereo order the other way round, each channel
        // turned so it stays on its side
        VisualizerCanvas {
            width: parent.width
            height: 36
            visible: root.visualizerLayout === "horizontal" && root._showVisualizer
            style: root.visualizerStyle
            bars: Visualizer.leftBars.slice().reverse().concat(Visualizer.rightBars.slice().reverse())
        }
    }
}
