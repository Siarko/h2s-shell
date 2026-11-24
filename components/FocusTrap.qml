import QtQuick

// Keeps Tab inside `scope` while `active`: Tab and Shift+Tab go to the next or previous
// control in it that takes the keyboard, wrapping round, never to one outside it. Its
// shortcuts work while the keyboard is inside the scope, or always with `holdsFocus`, which
// also brings the keyboard back in when it moves out (a click or tap that takes it). Put it
// anywhere in the window the scope is in.
//
// `take()` moves the keyboard into the scope, remembering the item outside that had it;
// `giveBack()` returns it there, unless it has gone somewhere else outside meanwhile.
//
//   FocusTrap { id: trap; scope: panel; active: root.open; holdsFocus: true }
Item {
    id: root

    property Item scope: null
    property bool active: false
    property bool holdsFocus: false

    // The item that had the keyboard before take()
    property Item _focusBefore: null

    function isInside(item) {
        for (let step = item; step; step = step.parent) {
            if (step === scope)
                return true;
        }
        return false;
    }

    function take() {
        const focused = Window.activeFocusItem;
        _focusBefore = focused && !isInside(focused) ? focused : null;
        scope.forceActiveFocus();
    }

    function giveBack() {
        const focused = Window.activeFocusItem;
        if (focused && !isInside(focused) && focused !== Window.contentItem)
            return;
        if (_focusBefore && _focusBefore.visible)
            _focusBefore.forceActiveFocus();
        _focusBefore = null;
    }

    // Tab inside the scope: the next control there that takes the keyboard (`forward`, else
    // the one before), wrapping round. None and the keyboard not inside: the scope itself
    function cycle(forward) {
        const start = Window.activeFocusItem;
        let item = start ?? scope;
        for (let step = 0; step < 1000 && item; step++) {
            item = item.nextItemInFocusChain(forward);
            if (item && item !== scope && isInside(item) && item.visible && item.enabled) {
                item.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
                return;
            }
            if (item === start)
                break;
        }
        if (!isInside(Window.activeFocusItem))
            scope.forceActiveFocus();
    }

    readonly property Item _focused: Window.activeFocusItem
    readonly property bool _working: active && scope !== null && scope.visible && (holdsFocus || isInside(_focused))

    on_FocusedChanged: {
        if (active && holdsFocus && _focused && !isInside(_focused))
            Qt.callLater(() => {
                const focused = Window.activeFocusItem;
                if (root.active && root.holdsFocus && focused && !root.isInside(focused))
                    root.scope.forceActiveFocus();
            });
    }

    // Shortcuts, not key handlers: a control that takes Tab itself (activeFocusOnTab) would
    // hand the keyboard on through the whole window's chain before a handler saw the key.
    // A modal over a side panel: only the modal has the keyboard, so only its trap works and
    // the keys are never ambiguous
    Shortcut {
        sequence: "Tab"
        enabled: root._working
        onActivated: root.cycle(true)
    }
    Shortcut {
        sequences: ["Backtab", "Shift+Tab"]
        enabled: root._working
        onActivated: root.cycle(false)
    }
}
