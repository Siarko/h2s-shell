import QtQuick
import qs.singletons

TestCase {
    suiteName: "PointerRules"

    function run() {
        // --- telling a tap from a click ---
        assert(!PointerRules.pressIsTouch(Qt.MouseEventNotSynthesized), "a real mouse press is not touch");
        assert(PointerRules.pressIsTouch(Qt.MouseEventSynthesizedByQt), "a press Qt made from a touch is");
        assert(PointerRules.pressIsTouch(Qt.MouseEventSynthesizedBySystem), "so is one the system made");

        // --- what a press that toggles a popup does ---
        assertEqual(PointerRules.popupClick(false, false, false), "open", "nothing open: it opens");
        assertEqual(PointerRules.popupClick(true, true, true), "close", "open from this entry: it closes");
        assertEqual(PointerRules.popupClick(true, true, false), "open", "open from another entry of the same type: it switches here");
        assertEqual(PointerRules.popupClick(true, false, false), "open", "another widget's popup open: this one's opens");
        assertEqual(PointerRules.popupClick(false, true, true), "open", "closed, this entry the last to open it: it opens");
    }
}
