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
        // Coming back to the machine: a security key plugged in just now is looked for at once
        if (!_awake)
            LockAuth.nudge()
        _awake = true
        Lockscreen.promptActive = true
        _sleepTimer.restart()
    }

    function _sleep() {
        _awake = false
        Lockscreen.promptActive = false
        // A question left unanswered (a one-time code) is not kept waiting
        LockAuth.cancelPassword()
        _prompt.reset()
        _keys.forceActiveFocus()
    }

    // A surface goes away with its screen — and a laptop's screen goes away and comes
    // back over a suspend. One that held the prompt has to give it up then: the surface
    // made for the screen that comes back would otherwise never wake, the prompt being
    // "active" on one that no longer exists.
    Component.onDestruction: {
        if (_awake) {
            Lockscreen.promptActive = false
            LockAuth.cancelPassword()
        }
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
        Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }
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

    // A key wakes the prompt as the pointer does — the only way in when there is no
    // pointer to move (a touchpad that did not come back from hibernation). It holds the
    // keyboard while the prompt is hidden, the prompt's field being unable to; the key
    // that woke it is not lost, it starts the password.
    Item {
        id: _keys
        focus: true
        Component.onCompleted: forceActiveFocus()
        Keys.onPressed: event => {
            root._wake()
            if (root._awake)
                _prompt.type(event.text)
        }
    }

    // Waking swaps the notifications for the prompt: they fade across, the prompt growing
    // slightly into place
    LockPrompt {
        id: _prompt
        anchors.centerIn: parent
        visible: opacity > 0
        opacity: root._awake ? 1 : 0
        scale: root._awake ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }
        Behavior on scale { NumberAnimation { duration: Theme.duration("enter"); easing: Theme.curve("enter") } }
        onActivity: root._wake()
    }

    ListView {
        readonly property bool shown: (Profiles.value("lockscreen.notificationsOnLock") ?? true) && !root._awake
        visible: opacity > 0
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }
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
