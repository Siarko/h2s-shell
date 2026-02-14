import QtQuick
import Quickshell.Io

Item {
    id: powerMenu
    implicitWidth: 200
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 8

        Repeater {
            model: [
                {
                    icon: "⏻",
                    label: "Shutdown",
                    script: "scripts/shutdown.sh"
                },
                {
                    icon: "↻",
                    label: "Restart",
                    script: "scripts/restart.sh"
                },
                {
                    icon: "󰍃",
                    label: "Logout",
                    script: "scripts/logout.sh"
                }
            ]

            Rectangle {
                required property var modelData

                width: powerMenu.width
                height: 44
                radius: 8
                color: buttonArea.containsMouse ? "#5a5a5a" : "#3b3b3b"

                Row {
                    anchors.centerIn: parent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 10

                    Text {
                        text: modelData.icon
                        font.pixelSize: 18
                        color: "white"
                    }

                    Text {
                        text: modelData.label
                        font.pixelSize: 16
                        color: "white"
                    }
                }

                MouseArea {
                    id: buttonArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        proc.command = ["bash", modelData.script];
                        proc.startDetached();
                    }
                }

                Process {
                    id: proc
                }
            }
        }
    }
}
