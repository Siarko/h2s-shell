import QtQuick
import qs.singletons

// The power popup: shut down, restart, log out (Session)
Item {
    id: powerMenu
    implicitWidth: Theme.popupWidth("power", 200)
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
                    run: () => Session.shutdown()
                },
                {
                    icon: "↻",
                    label: "Restart",
                    run: () => Session.restart()
                },
                {
                    icon: "󰍃",
                    label: "Logout",
                    run: () => Session.logout()
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
                    onClicked: modelData.run()

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
            }
        }
    }
}
