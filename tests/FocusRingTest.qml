import QtQuick
import qs.components
import qs.tests

// components/FocusRing.qml's memory of where the focus went, with its seam (`focused` and
// `windowFocusItem` set by hand), in the orders a compositor may give: the focus leaving
// before or after the window has no item with the keyboard (a window made inactive: Hyprland
// may say so only after the focus has left), and coming back before or after the window's
// item does. A ring out after a click comes back out, one lit by the keyboard comes back
// lit; the focus that went to another control is decided anew when it comes back.
// The real window's order: FocusRingInputTest.
TestCase {
    id: suite
    suiteName: "FocusRing"
    asynchronous: true

    property var _driver: WindowDriver {}
    property Item _control: Item {}
    property Item _other: Item {}
    property Component _ring: Component {
        FocusRing {
            // The seam: no window here
            windowFocusItem: null
        }
    }

    // Lets Qt.callLater run
    function _turn() {
        _driver.wait(20);
    }

    // A ring with the focus, lit (by the keyboard) or out (by a press)
    function _focusedRing(byPointer) {
        const ring = _ring.createObject(_control);
        ring.windowFocusItem = _other;
        _turn();
        if (byPointer)
            ring.pressed = true;
        ring.focused = true;
        ring.windowFocusItem = _control;
        ring.pressed = false;
        _turn();
        return ring;
    }

    function _check(byPointer, lossOrder, returnOrder) {
        const label = (byPointer ? "out after a click" : "lit by the keyboard") + ", " + lossOrder + ", " + returnOrder;
        const ring = _focusedRing(byPointer);
        assertEqual(ring.lit, !byPointer, label + ": as it starts");
        // The window goes
        if (lossOrder === "focus lost first") {
            ring.focused = false;
            _turn();
            ring.windowFocusItem = null;
        } else {
            ring.windowFocusItem = null;
            _turn();
            ring.focused = false;
        }
        _turn();
        assert(!ring.lit, label + ": away, not lit");
        // The window comes back, the focus with it (one delivery: both in one turn)
        if (returnOrder === "focus back first") {
            ring.focused = true;
            ring.windowFocusItem = _control;
        } else {
            ring.windowFocusItem = _control;
            ring.focused = true;
        }
        _turn();
        assertEqual(ring.lit, !byPointer, label + ": back as it was");
        ring.destroy();
    }

    function runAsync() {
        for (const byPointer of [true, false])
            for (const lossOrder of ["focus lost first", "window item gone first"])
                for (const returnOrder of ["focus back first", "window item back first"])
                    _check(byPointer, lossOrder, returnOrder);

        // The focus went to another control: coming back later is decided anew (Tab: lit)
        const moved = _focusedRing(true);
        moved.focused = false;
        moved.windowFocusItem = _other;
        _turn();
        moved.focused = true;
        moved.windowFocusItem = _control;
        _turn();
        assert(moved.lit, "out after a click, the focus to another control and back by the keyboard: lit");
        moved.destroy();

        // The window went, and came back with the keyboard elsewhere: nothing kept
        const elsewhere = _focusedRing(true);
        elsewhere.focused = false;
        _turn();
        elsewhere.windowFocusItem = null;
        _turn();
        elsewhere.windowFocusItem = _other;
        _turn();
        elsewhere.focused = true;
        elsewhere.windowFocusItem = _control;
        _turn();
        assert(elsewhere.lit, "back with the keyboard elsewhere, then reached by the keyboard: lit");
        elsewhere.destroy();
        finish();
    }
}
