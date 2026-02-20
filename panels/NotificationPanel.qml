import QtQuick
import QtQuick.Layouts
import qs.singletons

Item {
    id: root
    required property int screenHeight

    signal closeRequested

    implicitWidth: 350
    implicitHeight: screenHeight - 40 - 16

    // Set when "Clear all" is clicked; triggers success animation once list empties
    property bool clearing: false

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
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
                color: Theme.textPrimary
                Layout.fillWidth: true
            }

            Text {
                text: "Clear all"
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Theme.textSecondary
                visible: notificationList.count > 0

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (notificationList.count > 0) {
                            root.clearing = true;
                            Notifications.dismissAll();
                        }
                    }
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

            onCountChanged: {
                if (count === 0 && root.clearing) {
                    root.clearing = false;
                    successAnim.start();
                }
            }

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
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: true
                                color: Theme.textSubtle
                                Layout.fillWidth: true
                            }

                            Text {
                                text: Notifications.timestamps[delegateRoot.modelData.id] ?? ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textTertiary
                            }

                            Text {
                                text: "dismiss"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textTertiary

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: slideOut.start()
                                }
                            }
                        }

                        TextEdit {
                            text: delegateRoot.modelData.summary
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.bold: true
                            color: Theme.textPrimary
                            Layout.fillWidth: true
                            readOnly: true
                            selectByMouse: true
                            wrapMode: Text.NoWrap
                        }

                        TextEdit {
                            text: delegateRoot.modelData.body
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: Theme.textBody
                            Layout.fillWidth: true
                            readOnly: true
                            selectByMouse: true
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // Empty state
            Text {
                anchors.centerIn: parent
                text: "No notifications"
                font.family: Theme.fontFamily
                font.pixelSize: 14
                color: Theme.textTertiary
                visible: notificationList.count === 0 && successOverlay.opacity === 0
            }
        }
    }

    // Success overlay — shown after "Clear all" empties the list
    Item {
        id: successOverlay
        anchors.fill: parent
        visible: opacity > 0
        opacity: 0

        Rectangle {
            anchors.fill: parent
            color: Theme.popupBackground
        }

        Column {
            anchors.centerIn: parent
            spacing: 10

            Text {
                id: checkIcon
                anchors.horizontalCenter: parent.horizontalCenter
                text: "✓"
                font.family: Theme.fontFamily
                font.pixelSize: 52
                color: Theme.textPrimary
                scale: 0
                transformOrigin: Item.Center
            }

            Text {
                id: successLabel
                anchors.horizontalCenter: parent.horizontalCenter
                text: "All caught up"
                font.family: Theme.fontFamily
                font.pixelSize: 14
                color: Theme.textSecondary
                opacity: 0
            }
        }
    }

    SequentialAnimation {
        id: successAnim

        // Fade in panel + scale up checkmark
        ParallelAnimation {
            NumberAnimation {
                target: successOverlay
                property: "opacity"
                from: 0; to: 1
                duration: 180
            }
            NumberAnimation {
                target: checkIcon
                property: "scale"
                from: 0; to: 1
                duration: 380
                easing.type: Easing.OutBack
            }
        }

        // Fade in subtitle
        NumberAnimation {
            target: successLabel
            property: "opacity"
            from: 0; to: 1
            duration: 200
        }

        PauseAnimation { duration: 750 }

        // Fade everything out
        NumberAnimation {
            target: successOverlay
            property: "opacity"
            from: 1; to: 0
            duration: 200
        }

        ScriptAction {
            script: {
                checkIcon.scale = 0;
                successLabel.opacity = 0;
                root.closeRequested();
            }
        }
    }
}
