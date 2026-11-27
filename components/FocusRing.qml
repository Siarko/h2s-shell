import QtQuick
import qs.singletons

// The keyboard's ring: the one look every control shows while it has the keyboard. A line
// of the theme's `focusRing` colour and `focus.width`, `focus.gap` outside the control's
// edge, its corners following the control's (`radius`, a round control's ring round too);
// `inside` draws it within the edge instead, for an entry of a list that clips what is
// outside it. It is drawn around this item, which fills its parent unless placed otherwise
// (a part of the control: a checkbox's box, a slider's knob).
//
// Shown while `focused` — the control has the keyboard — when the keyboard brought it there
// (Tab, Shift+Tab, a control's own keys) or the code did, never when the pointer did: a
// press on the control, or within the least target round it (Theme.target), that gives it
// the focus does not light it, and a press on a control lit already puts it out. `pressed`
// adds a press the control sees elsewhere (a slider's track beside its knob). `shown` draws
// it whatever the focus: a preview (the mockups' keyboard states) or a list's keys' entry.
//
//   FocusRing { focused: root.activeFocus; shown: root.shownFocused; radius: root.radius }
Item {
    id: root

    property bool focused: false
    property bool shown: false
    property bool inside: false
    property bool pressed: false
    property real radius: parent?.radius ?? 0
    // Drawn now
    readonly property bool lit: shown || (focused && !_byPointer)
    // For tests and tools that look for the ring of a control
    readonly property bool focusRing: true

    // The focus came with the pointer (or the pointer pressed since): no ring until it leaves
    property bool _byPointer: false
    // The handler lets a press go after the control has handled its release, so a control
    // that takes the focus on the click is seen as the pointer's too
    readonly property bool _pointerDown: _press.active || pressed

    readonly property real _reach: inside ? 0 : Theme.focus.gap + Theme.focus.width

    anchors.fill: parent
    // Over the control's own areas: the press reaches this item's handler first, which only
    // watches it (a passive grab) and passes it on
    z: 1

    onFocusedChanged: _byPointer = focused && _pointerDown
    on_PointerDownChanged: {
        if (_pointerDown && focused)
            _byPointer = true;
    }

    PointHandler {
        id: _press
        margin: Theme.target.minSize / 2
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -root._reach
        visible: root.lit
        radius: root.radius > 0 ? root.radius + root._reach : 0
        color: "transparent"
        border.width: Theme.focus.width
        border.color: Theme.focusRing
    }
}
