import QtQuick
import qs.singletons

// Pill-style toast for shell-internal notifications (category: x-qs-shell).
// Appears at the bottom-center of the screen, slides up from below.
Item {
    id: root

    required property int screenWidth
    required property int screenHeight
    required property var screenModelData

    readonly property int pillWidth: 260
    readonly property int pillHeight: 40
    readonly property int bottomMargin: 40   // clearance from screen bottom edge
    readonly property int restY: screenHeight - pillHeight - bottomMargin

    x: (screenWidth - pillWidth) / 2
    y: screenHeight   // start off-screen below
    width: pillWidth
    height: pillHeight

    property var currentNotif: null

    function showNext() {
        const notif = Notifications.dequeueShellNotification();
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

        function onShellQueueChanged() {
            if (Workspaces.focused?.monitor?.name !== root.screenModelData.name)
                return;
            if (root.currentNotif !== null)
                return;
            if (slideOut.running)
                return;
            root.showNext();
        }

        function onShellQueueCleared() {
            autoCloseTimer.stop();
            if (root.currentNotif !== null)
                slideOut.start();
        }
    }

    NumberAnimation {
        id: slideIn
        target: root
        property: "y"
        from: root.screenHeight
        to: root.restY
        duration: 250
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: slideOut
        target: root
        property: "y"
        to: root.screenHeight
        duration: 200
        easing.type: Easing.InCubic
        onStopped: root.showNext()
    }

    Timer {
        id: autoCloseTimer
        interval: 2500
        onTriggered: root.dismiss()
    }

    Rectangle {
        width: root.pillWidth
        height: root.pillHeight
        topRightRadius: root.pillHeight / 2
        topLeftRadius: topRightRadius
        color: Qt.rgba(0, 0, 0, 0.65)

        Text {
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: 16
                rightMargin: 16
                verticalCenter: parent.verticalCenter
            }
            text: root.currentNotif?.summary ?? ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: Theme.textPrimary
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dismiss()
        }
    }
}
