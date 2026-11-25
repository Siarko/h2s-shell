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
// it, not one typed while the prompt fades in, not one typed on another screen.
//
// The catcher is a hidden text input, so that text which no single key event carries still
// arrives: a dead key and the letter after it (´ then e: "é"), a Compose sequence, an input
// method's commit. Qt composes those only for an item that accepts input methods — a plain
// Item gets the dead key as a key without text, and the "é" was lost. What it commits is
// sent on as a `key` event with that text, and the catcher's own text is emptied at once,
// so what is typed is held in one place only: the prompt's field.
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
    // Between the notifications or the prompt and the screen's edge
    readonly property int _margin: 16

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
    // Unconditional: Qt may drop the surface's properties before its destruction runs, and
    // the lock forgets only a surface it has (a surface never registered is left alone)
    Component.onDestruction: {
        _gone = true;
        Lockscreen.removeSurface(root);
    }

    // The rules' forwardKey effect, addressed to this instance
    function applyKey(key, text) {
        _prompt.applyKey(key, text);
    }

    // Motion counts only where the pointer really moved (LockIoRules.pointerMoved): a
    // surface appearing under a resting pointer gets an enter and hover events at one
    // place, and so does every frame of the fade (Qt Quick re-sends the hover when what
    // is under the pointer changes) — those would wake the prompt on every lock. A press is
    // always somebody.
    property var _lastPointer: null

    function _pointerAt(x, y) {
        const moved = LockIoRules.pointerMoved(_lastPointer, x, y);
        _lastPointer = { x: x, y: y };
        if (moved && _surfaceId !== null)
            Lockscreen.surfaceActivity(root);
    }

    function _pointerPress(x, y) {
        _lastPointer = { x: x, y: y };
        if (_surfaceId !== null)
            Lockscreen.surfacePress(root);
    }

    function _key(key, text, autoRepeat) {
        if (_surfaceId !== null)
            Lockscreen.surfaceKey(root, key, text, autoRepeat);
    }

    // The lock fades in over the screen rather than cutting to it
    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }
    }

    // Above everything, every button. Only the left button goes on to what is under it
    // (the Unlock button, the field's cursor); every other button stops here: a middle
    // click on a text input pastes the primary selection — whatever was last selected on
    // the desktop would land in the password — and a right click is nobody's business here.
    MouseArea {
        anchors.fill: parent
        z: 100
        hoverEnabled: true
        propagateComposedEvents: true
        acceptedButtons: Qt.AllButtons
        // Hidden while the prompt sleeps (on every screen), shown while it is awake
        cursorShape: root._view.promptSurface !== null ? Qt.ArrowCursor : Qt.BlankCursor
        onPositionChanged: mouse => { root._pointerAt(mouse.x, mouse.y); mouse.accepted = false }
        // A press of any button brings the prompt to this surface (the rules decide); a
        // left press goes on to what is under it, any other is taken here
        onPressed: mouse => {
            root._pointerPress(mouse.x, mouse.y);
            mouse.accepted = mouse.button !== Qt.LeftButton;
        }
        onReleased: mouse => { mouse.accepted = mouse.button !== Qt.LeftButton }
        onClicked: mouse => { mouse.accepted = mouse.button !== Qt.LeftButton }
    }

    // The key catcher: the one place keys arrive (see the header). A key is sent as it
    // comes — Return and the keypad's Enter both as "Enter", a character in `text`, a held
    // key's repeats saying so (the rules ignore a repeated Escape) — and taken, so the
    // catcher itself never edits. Text composed by Qt (dead keys, Compose, an input method)
    // comes as a commit instead of a key: sent on with that text, and emptied at once.
    // Invisible, and marked as a password to the input method: nothing predicted, learned
    // or shown; a preedit (an input method's text before its commit) never shows. Placed
    // outside the surface, where no pointer can reach it (a middle click on it would paste
    // the primary selection into the password); no selection by mouse, none kept; a plain
    // TextInput has no context menu and takes no drops. The field (LockPrompt) is covered by
    // the MouseArea above, which keeps every button but the left from it.
    TextInput {
        id: _keys
        x: -100
        y: -100
        width: 1
        height: 1
        persistentSelection: false
        opacity: 0
        focus: true
        echoMode: TextInput.Password
        inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        activeFocusOnPress: false
        activeFocusOnTab: false
        selectByMouse: false
        cursorVisible: false
        Accessible.ignored: true

        Keys.onPressed: event => {
            event.accepted = true;
            root._key(LockIoRules.keyName(event.key), event.text, event.isAutoRepeat);
        }

        onTextChanged: {
            if (text === "")
                return;
            const committed = text;
            text = "";
            root._key("", committed, false);
        }
    }

    // Waking swaps the notifications for the prompt: they fade across, the prompt growing
    // slightly into place. Never wider than the screen leaves room for (a small output, a
    // large scale)
    LockPrompt {
        id: _prompt
        anchors.centerIn: parent
        width: Math.min(implicitWidth, root.width - 2 * root._margin)
        view: root._view
        awake: root._awake
        capsLock: Lockscreen.capsLock === true
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

    // The notifications, at the detail the lock screen's setting allows (app only by
    // default: their text is not for whoever stands at the screen). Gone while the lock
    // screen is plain black (Idle.lockBlack: its screen-off reached and a monitor not read as
    // off), until input
    NotificationList {
        readonly property bool shown: (Profiles.value("lockscreen.notificationsOnLock") ?? true) && !root._awake
                                      && !Idle.lockBlack
        visible: opacity > 0
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }
        anchors {
            top: parent.top
            right: parent.right
            topMargin: root._margin
            rightMargin: root._margin
        }
        width: Math.min(Theme.lockNotificationsWidth, root.width - 2 * root._margin)
        height: Math.min(contentHeight, root.height - 2 * root._margin)
        detail: Profiles.value("lockscreen.lockNotificationDetail") ?? "app"
    }
}
