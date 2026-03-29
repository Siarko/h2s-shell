import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.hud
import qs.singletons

// Generic full-screen overlay for transient HUD components (toasts, OSD, etc.).
// Transparent and click-through everywhere except active HUD cards.
PanelWindow {
    id: hud
    required property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "hud"

    anchors {
        top: true
        left: true
    }
    implicitWidth: hud.screen.width
    implicitHeight: hud.screen.height
    margins { top: 0; left: 0 }
    color: "transparent"

    // Input passthrough: only forward clicks to visible HUD card areas.
    // notifItem.x starts at screenWidth (off-screen) so the region covers nothing
    // until the toast slides in, at which point it covers the card exactly.
    mask: Region {
        Region { item: notifItem }
        Region { item: queueBadge }
        Region { item: volumeOsd }
        Region { item: shellNotifItem }
    }

    NotificationHudItem {
        id: notifItem
        screenWidth: hud.implicitWidth
        screenModelData: hud.modelData
    }

    VolumeOsdItem {
        id: volumeOsd
        screenWidth: hud.implicitWidth
        screenHeight: hud.implicitHeight
    }

    ShellNotificationHudItem {
        id: shellNotifItem
        screenWidth: hud.implicitWidth
        screenHeight: hud.implicitHeight
        screenModelData: hud.modelData
    }

    // Badge showing how many notifications are waiting in the queue.
    // Positioned flush to the right screen edge, just below the bar.
    Rectangle {
        id: queueBadge
        x: hud.implicitWidth - width
        y: Config.bar.layout.reservedSpace + 16
        width: 36
        height: notifItem.height
        topLeftRadius: 6
        bottomLeftRadius: 6
        color: Theme.cellDefault

        opacity: Notifications.hudQueue.length > 0 ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

        Text {
            anchors.centerIn: parent
            text: Notifications.hudQueue.length
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            font.bold: true
            color: Theme.textPrimary
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Notifications.openPanelRequested()
        }
    }
}
