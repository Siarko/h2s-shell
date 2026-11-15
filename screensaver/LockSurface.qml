import QtQuick
import Quickshell.Wayland
import qs.singletons

// One lock surface instance: a view of Lockscreen.view, and the place this screen's input
// is reported from. It decides nothing — whether the prompt shows here, when the field
// empties, what a key does: the rules say (singletons/LockRules.qml).
//
// Keys arrive in exactly one place: the key catcher below, which holds the window's focus
// for the instance's whole life (the field never takes focus). Every key goes to the rules
// as a `key` event, and comes back as a forwardKey effect to the surface showing the prompt
// — this one or another — which edits its field (LockIoRules.editField). So no key is lost
// to a focus change: not the one that wakes the prompt, not Enter or Backspace right after
// it, not one typed while the prompt fades in, not one typed on another screen. (What a key
// event does not carry is not typed: dead keys, compose sequences and input methods do not
// work in the field yet.)
//
// Input is reported with this object itself (Lockscreen acts only for the LockSurface it
// registered), never by an id another component could guess.
WlSessionLockSurface {
    id: root

    color: "transparent"

    // The driver's id for this instance; null until registered (once the screen is known —
    // Quickshell sets it right after creating the instance)
    property var _surfaceId: null
    property bool _gone: false

    readonly property var _view: Lockscreen.view
    readonly property bool _awake: _surfaceId !== null && _view.promptSurface === _surfaceId

    function _register() {
        if (_surfaceId !== null || _gone || !screen)
            return;
        _surfaceId = Lockscreen.addSurface(root, screen.name);
    }

    onScreenChanged: _register()
    Component.onCompleted: {
        _register();
        _keys.forceActiveFocus();
    }
    Component.onDestruction: {
        _gone = true;
        if (_surfaceId !== null)
            Lockscreen.removeSurface(root);
    }

    // The rules' forwardKey effect, addressed to this instance
    function applyKey(key, text) {
        _prompt.applyKey(key, text);
    }

    // Pointer events in the first moments are the surface appearing under a resting
    // pointer, not somebody moving it: they would wake the prompt on every lock. Keys are
    // never filtered.
    property bool _pointerReady: false
    Timer { interval: 300; running: true; onTriggered: root._pointerReady = true }

    function _pointerActivity() {
        if (_pointerReady && _surfaceId !== null)
            Lockscreen.surfaceActivity(root);
    }

    function _pointerPress() {
        if (_pointerReady && _surfaceId !== null)
            Lockscreen.surfacePress(root);
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
        cursorShape: root._view.promptSurface !== null ? Qt.ArrowCursor : Qt.BlankCursor
        onPositionChanged: mouse => { root._pointerActivity(); mouse.accepted = false }
        // A press anywhere brings the prompt to this surface (the rules decide); it goes
        // on to what is under it, the Unlock button
        onPressed: mouse => { root._pointerPress(); mouse.accepted = false }
        onReleased: mouse => { mouse.accepted = false }
        onClicked: mouse => { mouse.accepted = false }
    }

    // The key catcher: the one place keys arrive (see the header). Return and the keypad's
    // Enter both come as "Enter"; a character travels in `text`; a held key's repeats say
    // so (the rules ignore a repeated Escape).
    Item {
        id: _keys
        focus: true
        Keys.onPressed: event => {
            event.accepted = true;
            if (root._surfaceId !== null)
                Lockscreen.surfaceKey(root, LockIoRules.keyName(event.key), event.text, event.isAutoRepeat);
        }
    }

    // Waking swaps the notifications for the prompt: they fade across, the prompt growing
    // slightly into place
    LockPrompt {
        id: _prompt
        anchors.centerIn: parent
        view: root._view
        awake: root._awake
        visible: opacity > 0
        opacity: root._awake ? 1 : 0
        scale: root._awake ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }
        Behavior on scale { NumberAnimation { duration: Theme.duration("enter"); easing: Theme.curve("enter") } }
        onSubmitted: text => {
            if (root._surfaceId !== null)
                Lockscreen.surfaceSubmit(root, text);
        }
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
