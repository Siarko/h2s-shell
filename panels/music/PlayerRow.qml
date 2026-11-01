import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.components
import qs.singletons

// One player in the music panel's list: its application's icon (a note when it has none),
// its name — accent and bold for the active one — and its buttons. Listed: play it alone
// (pause while it plays) and hide it; hidden: dimmed, with only show. Clicking a listed
// player's name makes it the active one.
Item {
    id: root

    required property MprisPlayer player
    property bool hidden: false

    readonly property bool _active: !hidden && player === Music.activePlayer
    readonly property bool _playing: player?.playbackState === MprisPlaybackState.Playing
    readonly property string _icon: Music.playerIcon(player)

    implicitHeight: Math.max(24, _name.implicitHeight + 6)

    // A glyph that does something, brighter under the pointer
    component RowButton: Text {
        id: _button
        property string tip: ""
        signal clicked
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBodyLarge
        color: _buttonArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
        horizontalAlignment: Text.AlignHCenter
        Layout.preferredWidth: 22

        MouseArea {
            id: _buttonArea
            anchors.fill: parent
            anchors.margins: -3
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: _button.clicked()
        }

        HoverTip {
            target: _button
            shown: _buttonArea.containsMouse && _button.tip !== ""
            text: _button.tip
            delay: 600
        }
    }

    // The row under the pointer, so a click on the name is seen to pick it
    Rectangle {
        anchors.fill: parent
        radius: Theme.button.radius
        color: _nameArea.containsMouse ? Theme.fillSubtle : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
    }

    RowLayout {
        anchors { fill: parent; leftMargin: 6; rightMargin: 4 }
        spacing: 8
        opacity: root.hidden ? 0.6 : 1

        Item {
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16

            Image {
                anchors.fill: parent
                visible: root._icon !== ""
                source: root._icon
                sourceSize: Qt.size(32, 32)
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            Text {
                anchors.centerIn: parent
                visible: root._icon === ""
                text: "󰝚"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: root._active ? Theme.accent : Theme.textSecondary
            }
        }

        Text {
            id: _name
            Layout.fillWidth: true
            text: root.player?.identity || root.player?.desktopEntry || "Player"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            font.bold: root._active
            color: root._active ? Theme.accent : Theme.textSecondary
            elide: Text.ElideRight

            MouseArea {
                id: _nameArea
                anchors.fill: parent
                enabled: !root.hidden
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Music.selectPlayer(root.player)
            }
        }

        RowButton {
            visible: !root.hidden
            text: root._playing ? "󰏤" : "󰐊"
            tip: root._playing ? "Pause" : "Play here, pause the others"
            onClicked: Music.togglePlayer(root.player)
        }

        RowButton {
            visible: !root.hidden
            text: "󰈉"
            tip: "Hide"
            onClicked: Music.hidePlayer(root.player)
        }

        RowButton {
            visible: root.hidden
            text: "󰈈"
            tip: "Show"
            onClicked: Music.showPlayer(root.player)
        }
    }
}
