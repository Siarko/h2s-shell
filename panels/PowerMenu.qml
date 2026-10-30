import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

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
                height: Theme.powerMenu.buttonHeight
                radius: Theme.powerMenu.buttonRadius
                color: buttonArea.containsMouse ? Theme.surfaceHover : Theme.surface
                Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

                MouseArea {
                    id: buttonArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: proc.running = true

                    Row {
                        anchors.centerIn: parent
                        spacing: 10

                        Text {
                            text: modelData.icon
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeHeading
                            color: Theme.textPrimary
                        }

                        Text {
                            text: modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSection
                            color: Theme.textPrimary
                        }
                    }
                }

                Process {
                    id: proc
                    command: ["bash", modelData.script]
                    workingDirectory: Quickshell.shellDir
                }
            }
        }
    }
}
