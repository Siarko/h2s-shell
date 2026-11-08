import QtQuick
import QtTest as QT
import Quickshell
import Quickshell.Wayland
import qs.components

// The bar's cells under real input events: a mouse, a finger (QtTest's touch screen),
// and what each does to hover and to a popup. What Qt makes of a touch is what this
// guards — measured on the Framework 12 (docs/plans/touch.md, stage 0), relied on by
// BarWidget and PopupWidget. The rules alone: PointerRulesTest. A stylus cannot be sent
// from QtTest; it was checked on the device.
//
// Opens a small window in a corner of the screen for a moment (a layer surface, so it
// moves no windows).
TestCase {
    id: root
    suiteName: "PointerInput"
    asynchronous: true

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 400
        implicitHeight: 160
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Row {
            spacing: 20

            // Somewhere for the mouse to go that is neither cell
            Item {
                id: away
                width: 40
                height: 40
            }

            BarWidget {
                id: cell
                width: 100
                height: 40
                property var hovers: []
                property int clicks: 0
                onHover: state => hovers.push(state)
                onClicked: clicks++
            }

            // For the finger only: after a QtTest mouse click, moving the mouse away leaves
            // the clicked cell still hovered (traced: no leave until another event), which a
            // tap on the same cell then reported as hover ending
            BarWidget {
                id: touchCell
                width: 60
                height: 40
                property var hovers: []
                property int clicks: 0
                onHover: state => hovers.push(state)
                onClicked: clicks++
            }

            PopupWidget {
                id: popupCell
                width: 100
                height: 40
                widgetType: "clock"
                popup: fakePopup
            }
        }

        // Text fields under touch (TouchTextFocus): a field in a box, one inside an item of
        // no size (children outside their parent — what defeated an earlier search), a
        // button
        Item {
            id: fieldsArea
            y: 60
            width: 400
            height: 100

            InputField {
                id: boxedField
                x: 10; y: 10
                width: 160
            }
            Item {
                x: 200; y: 10
                TextInput {
                    id: bareField
                    width: 120; height: 26
                }
            }
            Rectangle {
                id: fieldsButton
                x: 10; y: 55
                width: 80; height: 30
                property int clicks: 0
                MouseArea {
                    anchors.fill: parent
                    onClicked: fieldsButton.clicks++
                }
            }
            TouchTextFocus {
                id: touchText
                property var taps: []
                onFieldTapped: onField => { taps.push(onField); }
            }
        }

        QT.TestCase {
            id: driver
            name: "PointerInputDriver"
            when: false
        }
    }

    // Records what PopupWidget asks of its popup
    property QtObject _fakePopup: QtObject {
        id: fakePopup
        property bool active: false
        property string contentType: ""
        property var calls: []

        function open(element, persistent, contentType, contentData, byTouch) {
            calls.push("open persistent=" + persistent + " byTouch=" + byTouch);
            fakePopup.active = true;
            fakePopup.contentType = contentType;
        }

        function close() {
            calls.push("close");
            fakePopup.active = false;
        }
    }

    // A finger held for `holdMs`: longer than the hover settles, so hover had its chance
    function _tap(item, holdMs = 150) {
        const touch = driver.touchEvent(item);
        touch.press(0, item, item.width / 2, item.height / 2).commit();
        driver.wait(holdMs);
        touch.release(0, item, item.width / 2, item.height / 2).commit();
        driver.wait(120);
    }

    function _reset() {
        driver.mouseMove(away, 5, 5);
        driver.wait(120);
        cell.hovers = [];
        cell.clicks = 0;
        touchCell.hovers = [];
        touchCell.clicks = 0;
        fakePopup.calls = [];
        fakePopup.active = false;
    }

    function runAsync() {
        driver.wait(300); // the window shown

        // --- the mouse: hover and click, as before ---
        _reset();
        driver.mouseMove(cell, 10, 10);
        driver.wait(120);
        assertEqual(cell.hovers.join(","), "true", "the mouse coming over the cell is hover");
        driver.mouseMove(away, 5, 5);
        driver.wait(50);
        assertEqual(cell.hovers.join(","), "true,false", "and leaving it, hover ends");
        driver.mouseClick(cell);
        driver.wait(50);
        assertEqual(cell.clicks, 1, "a mouse click is a click");
        assert(!cell.lastPressByTouch, "made by the mouse");

        // --- a finger: a click, never hover ---
        _reset();
        _tap(touchCell);
        assertEqual(touchCell.clicks, 1, "a tap is a click");
        assert(touchCell.lastPressByTouch, "made by touch");
        assertEqual(touchCell.hovers.join(","), "", "a tap is no hover: the finger down is not over the cell");

        // --- a popup in hover mode ---
        _reset();
        popupCell.popupMode = "hover";
        driver.mouseMove(popupCell, 10, 10);
        driver.wait(120);
        assertEqual(fakePopup.calls.join("; "), "open persistent=false byTouch=false",
                    "hover mode: the mouse over the cell opens it, to close when the mouse leaves");
        _reset();
        driver.mouseMove(popupCell, 10, 10);
        driver.wait(120);
        fakePopup.calls = [];
        driver.mouseClick(popupCell);
        driver.wait(50);
        assertEqual(fakePopup.calls.join("; "), "", "hover mode: a mouse click does nothing");
        _reset();
        _tap(popupCell);
        assertEqual(fakePopup.calls.join("; "), "open persistent=true byTouch=true",
                    "hover mode: a tap opens it, to stay, as touch");
        _tap(popupCell);
        assertEqual(fakePopup.calls.join("; "), "open persistent=true byTouch=true; close",
                    "and a second tap closes it");

        // --- a popup in click mode ---
        _reset();
        popupCell.popupMode = "click";
        driver.mouseClick(popupCell);
        driver.wait(50);
        assertEqual(fakePopup.calls.join("; "), "open persistent=true byTouch=false",
                    "click mode: a mouse click opens it, as the mouse");
        _reset();
        _tap(popupCell);
        assertEqual(fakePopup.calls.join("; "), "open persistent=true byTouch=true",
                    "click mode: a tap opens it, as touch");

        // --- text fields under touch ---
        _reset();
        _tap(boxedField, 60);
        _tap(bareField, 60);
        _tap(fieldsButton, 60);
        assertEqual(touchText.taps.join(","), "true,true,false",
                    "taps on a field, on a field inside an item of no size, on a button");
        assertEqual(fieldsButton.clicks, 1, "the button still gets its tap");
        touchText.taps = [];
        const touch = driver.touchEvent(boxedField);
        touch.press(0, boxedField, 3, boxedField.height / 2).commit();
        driver.wait(40);
        touch.release(0, boxedField, 3, boxedField.height / 2).commit();
        driver.wait(80);
        assertEqual(touchText.taps.join(","), "true", "a tap on a field's box, beside its text, is on the field");
        touchText.taps = [];
        // A drag starting on the button: scrolling, not a tap elsewhere
        const drag = driver.touchEvent(fieldsButton);
        drag.press(0, fieldsButton, 10, 15).commit();
        driver.wait(30);
        drag.move(0, fieldsButton, 10, -25).commit();
        driver.wait(30);
        drag.release(0, fieldsButton, 10, -25).commit();
        driver.wait(80);
        assertEqual(touchText.taps.join(","), "", "a drag is not a tap: nothing decided");
        touchText.taps = [];
        driver.mouseClick(boxedField);
        driver.wait(80);
        assertEqual(touchText.taps.join(","), "", "a mouse click is not watched");

        _reset();
        finish();
    }
}
