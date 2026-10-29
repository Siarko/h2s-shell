import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.singletons

PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "screensaver"
    WlrLayershell.exclusiveZone: -1

    anchors { top: true; left: true }
    margins { top: 0; left: 0 }
    implicitWidth: root.screen.width
    implicitHeight: root.screen.height
    // Transparent, with the black inside the fading layer: a black window appeared at
    // full black at once, and only the notifications on top of it faded
    color: "transparent"

    readonly property bool _show: Lockscreen.screensaverVisible && !Lockscreen.locked
    visible: _show || _content.opacity > 0.001

    Item {
        id: _content
        anchors.fill: parent
        opacity: root._show ? 1.0 : 0.0

        Rectangle {
            anchors.fill: parent
            color: Theme.scrim
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root._show ? (Profiles.value("lockscreen.fadeInDuration") ?? 800) : (Profiles.value("lockscreen.fadeOutDuration") ?? 400)
                easing.type: Easing.InOutQuad
            }
        }

        // Notification list — top right, below bar
        ListView {
            visible: Profiles.value("lockscreen.notificationsOnScreensaver") ?? true
            anchors {
                top: parent.top
                right: parent.right
                topMargin: 30
                rightMargin: 16
            }
            width: 360
            height: Math.min(contentHeight, root.height)
            clip: true
            spacing: 8
            model: Notifications.notifications
            interactive: false

            delegate: NotificationPreview {
                detail: Profiles.value("lockscreen.screensaverNotificationDetail") ?? "full"
            }
        }
    }
}
