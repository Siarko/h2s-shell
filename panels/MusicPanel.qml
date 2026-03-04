import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.components
import qs.singletons
import QtQuick.Effects

Item {
    id: root
    implicitWidth: 320
    implicitHeight: col.implicitHeight

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
