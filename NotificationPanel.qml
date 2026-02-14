import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property int screenHeight

    implicitWidth: 350
    implicitHeight: screenHeight - 40 - 16

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // Header
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8

            Text {
                text: "Notifications"
                font.pixelSize: 16
                font.bold: true
                color: "white"
                Layout.fillWidth: true
            }

            Text {
                text: "Clear all"
                font.pixelSize: 13
                color: "#aaaaaa"

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifications.dismissAll()
                }
            }
        }

        // Notification list
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: Notifications.notifications

            delegate: Rectangle {
                required property var modelData

                width: ListView.view.width
                implicitHeight: delegateCol.implicitHeight + 16
                radius: 8
                color: "#3b3b3b"

                ColumnLayout {
                    id: delegateCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: modelData.appName
                            font.pixelSize: 11
                            font.bold: true
                            color: "#bbbbbb"
                            Layout.fillWidth: true
                        }

                        Text {
                            text: "dismiss"
                            font.pixelSize: 11
                            color: "#888888"

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelData.dismiss()
                            }
                        }
                    }

                    Text {
                        text: modelData.summary
                        font.pixelSize: 14
                        font.bold: true
                        color: "white"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Text {
                        text: modelData.body
                        font.pixelSize: 12
                        color: "#cccccc"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // Empty state
            Text {
                anchors.centerIn: parent
                text: "No notifications"
                font.pixelSize: 14
                color: "#888888"
                visible: Notifications.notifications.count === 0
            }
        }
    }
}
