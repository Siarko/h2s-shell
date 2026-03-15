import QtQuick
import QtQuick.Layouts
import qs.singletons

// Self-contained notification toast. Manages its own queue consumption,
// slide-in/out animations, and auto-dismiss timer.
Item {
    id: root

    required property int screenWidth
    required property var screenModelData

    // Exposed so Hud.qml can include it in the input-passthrough Region mask
    readonly property Item card: notifCard

    property var currentNotif: null
    readonly property int cardWidth: 360

    // Resting x: shift left by an extra 28px (badge 36px - existing 16px gap) when
    // the queue badge is visible so the toast doesn't overlap it.
    readonly property int restX: screenWidth - cardWidth - (Notifications.hudQueue.length > 0 ? 44 : 16)

    // Start off-screen to the right; animations move it in and out
    x: screenWidth
    y: Config.bar.layout.reservedSpace + 16
    width: cardWidth
    height: notifCard.implicitHeight

    // Consume the next item from the shared queue and start the slide-in
    function showNext() {
        if (Notifications.hudPanelOpen) {
            currentNotif = null;
            return;
        }
        const notif = Notifications.dequeueHudNotification();
        if (!notif) {
            currentNotif = null;
            return;
        }
        currentNotif = notif;
        slideIn.start();
        autoCloseTimer.restart();
    }

    function dismiss() {
        autoCloseTimer.stop();
        slideOut.start();
    }

    Connections {
        target: Notifications

        function onHudQueueChanged() {
            // Only the screen that owns the focused workspace shows toasts
            if (Workspaces.focused?.monitor?.name !== root.screenModelData.name) return;
            if (root.currentNotif !== null) {
                // Toast already visible — nudge its x to account for badge appearing/disappearing
                if (!slideIn.running && !slideOut.running) {
                    nudge.restart();
                }
                return;
            }
            // Don't interrupt an ongoing slide-out
            if (slideOut.running) return;
            root.showNext();
        }

        function onHudQueueCleared() {
            autoCloseTimer.stop();
            if (root.currentNotif !== null) {
                slideOut.start();
            }
        }
    }

    NumberAnimation {
        id: slideIn
        target: root
        property: "x"
        from: root.screenWidth
        to: root.restX
        duration: 250
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: slideOut
        target: root
        property: "x"
        to: root.screenWidth
        duration: 200
        easing.type: Easing.InCubic
        onStopped: root.showNext()
    }

    // Nudge the resting toast when the badge appears/disappears mid-show.
    NumberAnimation {
        id: nudge
        target: root
        property: "x"
        to: root.restX
        duration: 200
        easing.type: Easing.OutCubic
    }

    Timer {
        id: autoCloseTimer
        interval: 5000
        onTriggered: root.dismiss()
    }

    Rectangle {
        id: notifCard
        width: root.cardWidth
        implicitHeight: contentColumn.implicitHeight + 20
        radius: 8
        color: Theme.cellDefault

        opacity: hoverHandler.hovered ? 0.6 : 1.0
        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
        }

        property var _hudReplyAction: (root.currentNotif?.actions ?? []).find(a => a.id === "inline-reply") ?? null

        function _hudSendReply() {
            if (_hudReplyInput.text.length === 0) return;
            notifCard._hudReplyAction.invoke(_hudReplyInput.text);
            root.dismiss();
        }

        HoverHandler { id: hoverHandler }

        ColumnLayout {
            id: contentColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 10
            }
            spacing: 4

            // Header: app name + close button
            RowLayout {
                Layout.fillWidth: true

                Image {
                    visible: (root.currentNotif?.appIcon ?? "") !== ""
                    source: visible ? "image://icon/" + root.currentNotif.appIcon : ""
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    Layout.maximumWidth: 16
                    Layout.maximumHeight: 16
                    fillMode: Image.PreserveAspectFit
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    text: root.currentNotif?.appName ?? ""
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    color: Theme.textSubtle
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    text: "×"
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    color: Theme.textSubtle

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismiss()
                    }
                }
            }

            // Summary
            Text {
                text: root.currentNotif?.summary ?? ""
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                color: Theme.textPrimary
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            // Body (optional — hidden when empty)
            Text {
                text: root.currentNotif?.body ?? ""
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textBody
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: (root.currentNotif?.body ?? "").length > 0
            }

            Image {
                visible: (root.currentNotif?.image ?? "") !== ""
                source: root.currentNotif?.image ?? ""
                Layout.fillWidth: true
                Layout.maximumHeight: 120
                fillMode: Image.PreserveAspectFit
                Layout.topMargin: 4
            }

            Row {
                spacing: 6
                visible: (root.currentNotif?.actions ?? []).filter(a => a.id !== "inline-reply").length > 0
                Layout.topMargin: 4

                Repeater {
                    model: (root.currentNotif?.actions ?? []).filter(a => a.id !== "inline-reply")
                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: _hudActionLabel.implicitWidth + 16
                        height: 24
                        radius: 5
                        color: Theme.sliderAccent

                        Text {
                            id: _hudActionLabel
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
                                root.dismiss();
                            }
                        }
                    }
                }
            }

            RowLayout {
                visible: notifCard._hudReplyAction !== null
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: 5
                    color: Qt.rgba(0, 0, 0, 0.2)

                    Text {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        text: "Reply…"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.textTertiary
                        verticalAlignment: Text.AlignVCenter
                        visible: _hudReplyInput.text.length === 0
                    }

                    TextInput {
                        id: _hudReplyInput
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.textPrimary
                        verticalAlignment: TextInput.AlignVCenter
                        onAccepted: notifCard._hudSendReply()
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
                        onClicked: notifCard._hudSendReply()
                    }
                }
            }
        }
    }
}
