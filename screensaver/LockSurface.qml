import QtQuick
import Quickshell.Wayland
import qs.singletons

WlSessionLockSurface {
    id: root

    color: "transparent"

    property bool _awake: false

    property bool _ready: false
    Timer { interval: 300; running: true; onTriggered: root._ready = true }

    function _wake() {
        if (!_ready) return
        if (Lockscreen.promptActive && !_awake) return
        _awake = true
        Lockscreen.promptActive = true
        _sleepTimer.restart()
    }

    function _sleep() {
        _awake = false
        Lockscreen.promptActive = false
        _prompt.reset()
    }

    Timer {
        id: _sleepTimer
        interval: 10000
        onTriggered: root._sleep()
    }

    // The lock fades in over the screen rather than cutting to it
    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing.type: Theme.easing("fade") } }
    }

    MouseArea {
        anchors.fill: parent
        z: 100
        hoverEnabled: true
        propagateComposedEvents: true
        cursorShape: Lockscreen.promptActive ? Qt.ArrowCursor : Qt.BlankCursor
        onEntered:                  root._wake()
        onPositionChanged: mouse => { root._wake(); mouse.accepted = false }
        onPressed:         mouse => { root._wake(); mouse.accepted = false }
        onReleased:        mouse => { mouse.accepted = false }
        onClicked:         mouse => { mouse.accepted = false }
    }

    // Waking swaps the notifications for the prompt: they fade across, the prompt growing
    // slightly into place
    LockPrompt {
        id: _prompt
        anchors.centerIn: parent
        visible: opacity > 0
        opacity: root._awake ? 1 : 0
        scale: root._awake ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing.type: Theme.easing("fade") } }
        Behavior on scale { NumberAnimation { duration: Theme.duration("enter"); easing.type: Theme.easing("enter") } }
        onActivity: root._wake()
    }

    ListView {
        readonly property bool shown: (Profiles.value("lockscreen.notificationsOnLock") ?? true) && !root._awake
        visible: opacity > 0
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing.type: Theme.easing("fade") } }
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 16
            rightMargin: 16
        }
        width: 360
        height: Math.min(contentHeight, root.height - 32)
        clip: true
        spacing: 8
        model: Notifications.notifications
        interactive: false

        delegate: NotificationPreview {
            detail: Profiles.value("lockscreen.lockNotificationDetail") ?? "full"
        }
    }
}
