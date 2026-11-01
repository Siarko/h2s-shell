import QtQuick
import qs.components
import qs.singletons
import qs.panels.music

// The music popup: players to pick from, the cover, the track, seeking, transport, and the
// visualiser (Visualizer's levels, drawn by VisualizerCanvas) beside them, below them or
// around the cover.
//
// In three parts: the player list held to the top, seeking and transport held to the
// bottom, and the cover and track between them. The panel is as tall as the popup shows it
// (fitsShownHeight), so while the popup moves to its size — here from another panel, or
// the list growing — the list and the controls stay in sight and the middle takes what is
// left, cut to it. At rest it is not cut, so the visualiser round the cover may reach past.
Item {
    id: root
    implicitWidth: Theme.popupWidth("music", 320)
    readonly property int _spacing: 8
    implicitHeight: (_list.visible ? _list.implicitHeight + _spacing : 0) + _carousel.implicitHeight
        + (_bottom.implicitHeight > 0 ? _spacing + _bottom.implicitHeight : 0)

    // Set by the popup (Popup.qml)
    property bool popupAnimating: false
    readonly property bool fitsShownHeight: true

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

    // The players, to pick, play alone, hide and show again
    PlayerList {
        id: _list
        anchors { top: parent.top; left: parent.left; right: parent.right }
    }

    // The active player's cover and track, sliding sideways to the next player's; in the
    // room between the list and the controls
    Item {
        anchors {
            top: _list.visible ? _list.bottom : parent.top
            topMargin: _list.visible ? root._spacing : 0
            bottom: _bottom.top
            bottomMargin: _bottom.implicitHeight > 0 ? root._spacing : 0
            left: parent.left
            right: parent.right
        }
        clip: root.popupAnimating || height < _carousel.implicitHeight - 0.5

        PlayerCarousel {
            id: _carousel
            width: parent.width
            visualizerLayout: root.visualizerLayout
            visualizerStyle: root.visualizerStyle
            showVisualizer: root._showVisualizer
        }
    }

    // Held to the bottom, but never up into the list: in a popup shorter than the list and
    // the controls (still growing from a smaller panel's size) they go on past its edge,
    // where the popup cuts them, rather than over the list
    readonly property real _leastHeight: (_list.visible ? _list.implicitHeight + _spacing : 0)
        + (_bottom.implicitHeight > 0 ? _spacing + _bottom.implicitHeight : 0)

    Column {
        id: _bottom
        y: Math.max(root.height, root._leastHeight) - height
        anchors { left: parent.left; right: parent.right }
        spacing: root._spacing

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
