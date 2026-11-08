import QtQuick
import qs.singletons

// Text fields under touch in a layer window (a popup, the HUD): tells the window when to
// take the keyboard, so an on-screen keyboard shows for a field and hides after, as in a
// browser. Put it over the window's content, filling it; the window binds its keyboard
// to `fieldTapped` (exclusive after a tap on a field, none after any other tap).
//
// Why it works this way — measured on the Framework (docs/plans/touch.md, "On-screen
// keyboard, researched"):
// - Qt asks for an on-screen keyboard (text-input enable) when its window gets the
//   keyboard, and on Qt 6.11 stops only when the window loses it — moving the focus inside
//   the window changes nothing. So the *window's* keyboard is what shows and hides it.
// - The window must hold the keyboard exclusively while typing: the keyboard's own panel
//   appearing makes Hyprland hand an on-demand layer's keyboard to whatever is under the
//   mouse cursor, a few milliseconds after the tap.
// - The field is found under the finger, not by focus: an item gets no active focus while
//   its window has no keyboard. Every field (or box holding one, as InputField) is tried
//   against its own outline — children often lie outside their parents (a Loader, a Column
//   of no size), so a walk down by the parents' outlines missed them.
// - It sits above the content and watches passively: a press goes to the topmost item that
//   takes it, so a watcher under the content saw only empty space; a PointHandler takes no
//   press, so fields and buttons still get theirs.
Item {
    id: root

    // Watch taps (a popup opened by touch); off, it does nothing
    property bool watching: true
    // Which presses count: a finger and a stylus. The device of a press is reliable (that of
    // a hover is not — BarWidget); the mouse keeps its own behaviour.
    property int acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Stylus
    // Where the fields are (by default what this sits on)
    property Item fieldsRoot: parent

    // After every tap: whether it landed on a text field. The window takes the keyboard
    // exclusively while the last tap did.
    signal fieldTapped(bool onField)

    // The focus off any field, as a tap elsewhere does (a tap outside the window)
    function release() {
        _neutral.forceActiveFocus();
        Qt.callLater(() => Qt.inputMethod.update(Qt.ImQueryInput));
    }

    function _isTextField(item) {
        return !!item && item.cursorPosition !== undefined && !item.readOnly && item.enabled;
    }

    // The text field under a point in this item's coordinates, or null
    function fieldAt(x, y) {
        let found = null;
        const visit = item => {
            for (const child of item.children) {
                if (child === root || !child.visible || child.opacity === 0)
                    continue;
                const field = _isTextField(child) ? child : _isTextField(child.input) ? child.input : null;
                if (field) {
                    const inside = root.mapToItem(child, x, y);
                    if (inside.x >= 0 && inside.y >= 0 && inside.x < child.width && inside.y < child.height)
                        found = field;
                }
                visit(child);
            }
        };
        if (fieldsRoot)
            visit(fieldsRoot);
        return found;
    }

    anchors.fill: parent
    z: 1000

    // Where the focus goes off a field: an item that takes no text
    Item {
        id: _neutral
    }

    PointHandler {
        enabled: root.watching
        acceptedDevices: root.acceptedDevices
        onActiveChanged: {
            if (!active)
                return;
            const field = root.fieldAt(point.position.x, point.position.y);
            if (!field)
                _neutral.forceActiveFocus();
            root.fieldTapped(field !== null);
            // Qt 6.12 drops text-input for a focus that takes none only when asked
            Qt.callLater(() => Qt.inputMethod.update(Qt.ImQueryInput));
        }
    }
}
