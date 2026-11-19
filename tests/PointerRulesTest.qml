import QtQuick
import qs.singletons

TestCase {
    suiteName: "PointerRules"

    function run() {
        // --- telling a tap from a click ---
        assert(!PointerRules.pressIsTouch(Qt.MouseEventNotSynthesized), "a real mouse press is not touch");
        assert(PointerRules.pressIsTouch(Qt.MouseEventSynthesizedByQt), "a press Qt made from a touch is");
        assert(PointerRules.pressIsTouch(Qt.MouseEventSynthesizedBySystem), "so is one the system made");

        // --- which presses toggle a popup ---
        assert(PointerRules.tapTogglesPopup("click", false), "click mode: a click");
        assert(PointerRules.tapTogglesPopup("click", true), "click mode: a tap");
        assert(!PointerRules.tapTogglesPopup("hover", false), "hover mode: a click does nothing, hovering opens it");
        assert(PointerRules.tapTogglesPopup("hover", true), "hover mode: a tap does, a finger cannot hover");
        assert(!PointerRules.tapTogglesPopup("none", false), "no popup: a click");
        assert(!PointerRules.tapTogglesPopup("none", true), "no popup: a tap");

        // --- what such a press does ---
        assertEqual(PointerRules.popupClick(false, false, false), "open", "nothing open: it opens");
        assertEqual(PointerRules.popupClick(true, true, true), "close", "open from this entry: it closes");
        assertEqual(PointerRules.popupClick(true, true, false), "open", "open from another entry of the same type: it switches here");
        assertEqual(PointerRules.popupClick(true, false, false), "open", "another widget's popup open: this one's opens");
        assertEqual(PointerRules.popupClick(false, true, true), "open", "closed, this entry the last to open it: it opens");
    }
}
