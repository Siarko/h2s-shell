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

                    property var _regularActions: {
                        const actions = delegateRoot.modelData.actions ?? [];
                        return actions.filter(a => a.id !== "inline-reply");
                    }

                    property var _replyAction: {
                        const actions = delegateRoot.modelData.actions ?? [];
                        return actions.find(a => a.id === "inline-reply") ?? null;
                    }

                    function _sendReply() {
                        if (_replyInput.text.length === 0) return;
                        card._replyAction.invoke(_replyInput.text);
                        slideOut.start();
                    }

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

                            Image {
                                visible: (delegateRoot.modelData.appIcon ?? "") !== ""
                                source: visible ? "image://icon/" + delegateRoot.modelData.appIcon : ""
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                Layout.maximumWidth: 16
                                Layout.maximumHeight: 16
                                fillMode: Image.PreserveAspectFit
                                Layout.alignment: Qt.AlignVCenter
                            }

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

                        Image {
                            visible: (delegateRoot.modelData.image ?? "") !== ""
                            source: delegateRoot.modelData.image ?? ""
                            Layout.fillWidth: true
                            Layout.maximumHeight: 160
                            fillMode: Image.PreserveAspectFit
                            Layout.topMargin: 4
                        }

                        Row {
                            spacing: 6
                            visible: card._regularActions.length > 0
                            Layout.topMargin: 4

                            Repeater {
                                model: card._regularActions
                                delegate: Rectangle {
                                    required property var modelData
                                    implicitWidth: _actionLabel.implicitWidth + 16
                                    height: 24
                                    radius: 5
                                    color: Theme.sliderAccent

                                    Text {
                                        id: _actionLabel
                                        anchors.centerIn: parent
                                        text: modelData.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        color: Theme.textPrimary
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            modelData.invoke();
                                            slideOut.start();
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            visible: card._replyAction !== null
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 5
                                color: Theme.popupBackground

                                Text {
                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                    text: "Reply…"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.textTertiary
                                    verticalAlignment: Text.AlignVCenter
                                    visible: _replyInput.text.length === 0
                                }

                                TextInput {
                                    id: _replyInput
                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.textPrimary
                                    verticalAlignment: TextInput.AlignVCenter
                                    onAccepted: card._sendReply()
                                }
                            }

                            Rectangle {
                                implicitWidth: 48
                                implicitHeight: 28
                                radius: 5
                                color: Theme.sliderAccent

                                Text {
                                    anchors.centerIn: parent
                                    text: "Send"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    color: Theme.textPrimary
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: card._sendReply()
                                }
                            }
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
