pragma Singleton

import Quickshell
import QtQuick

// How the shell tells a finger from a pointer. Pure functions, so tests/PointerRulesTest.qml
// checks them; tests/PointerInputTest.qml checks the events Qt really sends.
//
// Measured on the Framework 12: Qt turns a tap into a mouse
// press marked as synthesised, and a touch screen reports a press as hover — over while
// the finger is down — so hover from it means nothing. A stylus is a real pointer: it
// hovers when held above the screen, and its taps are ordinary mouse presses. The device a
// hover names is no guide (BarWidget, `hover`).
Singleton {
    id: root

    // From a MouseArea press's `source`: whether a touch screen made it
    function pressIsTouch(source: int): bool {
        return source !== Qt.MouseEventNotSynthesized;
    }

    // Whether a click or tap on a popup widget opens (or closes) its popup. In hover mode a
    // mouse click does nothing — hovering opens it — but a tap does: a finger cannot hover.
    function tapTogglesPopup(popupMode: string, byTouch: bool): bool {
        return popupMode === "click" || (popupMode === "hover" && byTouch);
    }

    // What a click (or tap) that toggles a popup does: "close" when the popup is open with
    // this widget's content and this widget opened it, else "open" — from another bar entry
    // of the same widget type it switches the open popup there, as hovering does.
    function popupClick(popupActive: bool, sameContent: bool, openedHere: bool): string {
        return popupActive && sameContent && openedHere ? "close" : "open";
    }
}
