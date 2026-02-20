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

    // Start off-screen to the right; animations move it in and out
    x: screenWidth
    y: 56   // 40px bar + 16px gap
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
            // Already showing something — wait for it to finish
            if (root.currentNotif !== null) return;
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
        to: root.screenWidth - root.cardWidth - 16
        duration: 250
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: slideOut
        target: root
        property: "x"
        from: root.screenWidth - root.cardWidth - 16
        to: root.screenWidth
        duration: 200
        easing.type: Easing.InCubic
        onStopped: root.showNext()
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
        }
    }
}
