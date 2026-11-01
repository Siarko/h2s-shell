import QtQuick
import Quickshell
import qs.components
import qs.singletons

// The music panel's players (Music): a "Hidden" expander over the list when the user has
// hidden some — open, it shows them, each to be shown again — then the listed players
// (PlayerRow). Scrolling over the list steps through the listed ones. Shown when there is
// more than one player, or any hidden one — a lone listed player, or none, still leads to
// the hidden.
Column {
    id: root

    spacing: 2
    visible: Music.listedPlayers.length > 1 || Music.hiddenPlayers.length > 0

    // Open for this panel only: it starts closed each time
    property bool hiddenOpen: false

    // "Hidden (n)", turning its chevron when open
    Item {
        width: root.width
        height: Music.hiddenPlayers.length > 0 ? Math.max(22, _hiddenLabel.implicitHeight + 6) : 0
        visible: Music.hiddenPlayers.length > 0

        Row {
            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
            spacing: 6

            Text {
                text: "󰅂"
                rotation: root.hiddenOpen ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: _hiddenArea.containsMouse ? Theme.textPrimary : Theme.textMuted
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                id: _hiddenLabel
                text: "Hidden (" + Music.hiddenPlayers.length + ")"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: _hiddenArea.containsMouse ? Theme.textPrimary : Theme.textMuted
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: _hiddenArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.hiddenOpen = !root.hiddenOpen
        }
    }

    Repeater {
        // ScriptModel, never the bare array — see "The Repeater crash" in
        // docs/ARCHITECTURE.md
        model: ScriptModel {
            values: root.hiddenOpen ? Music.hiddenPlayers : []
        }

        PlayerRow {
            required property var modelData
            width: root.width
            player: modelData
            hidden: true
        }
    }

    // The listed players; scrolling steps through them
    Item {
        width: root.width
        implicitHeight: _listed.implicitHeight

        Column {
            id: _listed
            width: parent.width
            spacing: 2

            Repeater {
                model: ScriptModel {
                    values: Music.visiblePlayers
                }

                PlayerRow {
                    required property var modelData
                    width: _listed.width
                    player: modelData
                }
            }
        }

        CustomMouseArea {
            anchors.fill: parent
            z: -1
            onScrollNotchY: direction => {
                const players = Music.visiblePlayers;
                const index = players.indexOf(Music.activePlayer);
                const next = Math.max(0, Math.min(players.length - 1, index - direction));
                if (players[next])
                    Music.selectPlayer(players[next]);
            }
        }
    }
}
