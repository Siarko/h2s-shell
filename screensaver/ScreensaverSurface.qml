import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.singletons

PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Overlay
    // The keyboard while shown: the key that wakes the screen goes nowhere (into a terminal
    // it would run a line). Given back the moment it hides, before the fade out ends
    WlrLayershell.keyboardFocus: _show ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "screensaver"
    WlrLayershell.exclusiveZone: -1

    anchors { top: true; left: true }
    margins { top: 0; left: 0 }
    implicitWidth: root.screen.width
    implicitHeight: root.screen.height
    // Transparent, with the black inside the fading layer: a black window appeared at
    // full black at once, and only the notifications on top of it faded
    color: "transparent"

    // What this screen shows (Idle.shownFor: "on" also while locked, where the lock screen
    // is what shows): the screensaver, or "off" — powered off, under this surface plain
    // black and at once (in case the power cut fails), still taking the keys
    readonly property string _way: Idle.shownFor(root.modelData?.name ?? "")
    readonly property bool _show: _way !== "on"
    readonly property bool _off: _way === "off"
    // The window is shown, still clear, before the fade in starts: mapping it and its
    // first frame took so long the first time that the start of the fade was lost
    property bool _mapped: false
    visible: _mapped

    // The screensaver turned into a monitor going off: black at once
    on_OffChanged: {
        if (_off && _show) {
            _firstFrame.running = false
            _fadeIn.stop()
            _content.opacity = 1
        }
    }

    on_ShowChanged: {
        if (_show) {
            _fadeOut.stop()
            _mapped = true
            if (_off) {
                _content.opacity = 1
                return
            }
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
        NotificationList {
            visible: !root._off && (Profiles.value("lockscreen.notificationsOnScreensaver") ?? true)
            anchors {
                top: parent.top
                right: parent.right
                topMargin: 30
                rightMargin: 16
            }
            width: 360
            height: Math.min(contentHeight, root.height)
            detail: Profiles.value("lockscreen.screensaverNotificationDetail") ?? "full"
        }
    }
}
