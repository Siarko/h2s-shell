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
    // The window is shown, still clear, before the fade in starts: mapping it and its
    // first frame took so long the first time that the start of the fade was lost
    property bool _mapped: false
    visible: _mapped

    on_ShowChanged: {
        if (_show) {
            _fadeOut.stop()
            _mapped = true
            _firstFrame.ticks = 0
            _firstFrame.running = true
        } else {
            _firstFrame.running = false
            _fadeIn.stop()
            _fadeOut.start()
        }
    }

    FrameAnimation {
        id: _firstFrame
        property int ticks: 0
        onTriggered: {
            // The first tick comes before the window's first frame, the second after it
            if (++ticks < 2)
                return
            running = false
            _fadeIn.start()
        }
    }

    NumberAnimation {
        id: _fadeIn
        target: _content
        property: "opacity"
        to: 1
        duration: Profiles.value("lockscreen.fadeInDuration") ?? 800
        easing.type: Easing.InOutQuad
    }

    NumberAnimation {
        id: _fadeOut
        target: _content
        property: "opacity"
        to: 0
        duration: Profiles.value("lockscreen.fadeOutDuration") ?? 400
        easing.type: Easing.InOutQuad
        onFinished: root._mapped = false
    }

    Item {
        id: _content
        anchors.fill: parent
        opacity: 0

        Rectangle {
            anchors.fill: parent
            color: Theme.scrim
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
