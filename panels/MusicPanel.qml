import QtQuick
import qs.components
import qs.singletons
import qs.panels.music

// The music popup: players to pick from, the cover, the track, seeking, transport, and the
// visualiser (Visualizer's levels, drawn by VisualizerCanvas) beside them, below them or
// around the cover
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

    PanelVisualizer {
        id: _visualizer
        anchors.fill: parent
        visualizerLayout: root.visualizerLayout
        visualizerStyle: root.visualizerStyle
        showVisualizer: root._showVisualizer
    }

    Column {
        id: col
        width: parent.implicitWidth
        spacing: 8

        // The players, to pick, play alone, hide and show again
        PlayerList {
            width: parent.width
        }

        // The active player's cover and track, sliding sideways to the next player's
        PlayerCarousel {
            width: parent.width
            visualizerLayout: root.visualizerLayout
            visualizerStyle: root.visualizerStyle
            showVisualizer: root._showVisualizer
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

        // The horizontal visualiser's place: PanelVisualizer draws it there, cut to the
        // popup's shape with the rest
        Item {
            width: parent.width
            height: _visualizer.stripHeight
            visible: root.visualizerLayout === "horizontal" && root._showVisualizer
        }
    }
}
