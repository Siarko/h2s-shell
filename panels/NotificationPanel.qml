import QtQuick
import QtQuick.Layouts
import qs.singletons

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
                color: Theme.textPrimary
                Layout.fillWidth: true
            }

            Text {
                text: "Clear all"
                font.pixelSize: 13
                color: Theme.textSecondary

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifications.dismissAll()
                }
            }
        }

        // Notification list
        ListView {
            id: notificationList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: Notifications.notifications

            delegate: Item {
                id: delegateRoot
                required property var modelData

                width: ListView.view.width
                implicitHeight: card.implicitHeight
                clip: true

                Connections {
                    target: Notifications
                    function onDismissAllRequested() {
                        slideOut.start();
                    }
                }

                SequentialAnimation {
                    id: slideOut

                    NumberAnimation {
                        target: card
                        property: "x"
                        to: delegateRoot.width
                        duration: 200
                        easing.type: Easing.InCubic
                    }

                    NumberAnimation {
                        target: delegateRoot
                        property: "implicitHeight"
                        to: 0
                        duration: 150
                        easing.type: Easing.InOutQuad
                    }

                    ScriptAction {
                        script: delegateRoot.modelData.tracked = false
                    }
                }

                Rectangle {
                    id: card
                    x: -delegateRoot.width
                    width: parent.width
                    Component.onCompleted: slideIn.start()

                    NumberAnimation {
                        id: slideIn
                        target: card
                        property: "x"
                        from: -delegateRoot.width
                        to: 0
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                    implicitHeight: delegateCol.implicitHeight + 16
                    radius: 8
                    color: Theme.cellDefault

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
                                text: delegateRoot.modelData.appName
                                font.pixelSize: 11
                                font.bold: true
                                color: Theme.textSubtle
                                Layout.fillWidth: true
                            }

                            Text {
                                text: "dismiss"
                                font.pixelSize: 11
                                color: Theme.textTertiary

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: slideOut.start()
                                }
                            }
                        }

                        Text {
                            text: delegateRoot.modelData.summary
                            font.pixelSize: 14
                            font.bold: true
                            color: Theme.textPrimary
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Text {
                            text: delegateRoot.modelData.body
                            font.pixelSize: 12
                            color: Theme.textBody
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // Empty state
            Text {
                anchors.centerIn: parent
                text: "No notifications"
                font.pixelSize: 14
                color: Theme.textTertiary
                visible: notificationList.count === 0
            }
        }
    }
}
