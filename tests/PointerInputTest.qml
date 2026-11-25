import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.singletons

// The bar's cells under real input events: a mouse, a finger (QtTest's touch screen),
// what each does to hover and to a popup, and the interactions a cell reports
// (BarWidget.interaction). What Qt makes of a touch is what this
// guards — measured on the Framework 12, relied on by
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
        implicitHeight: 380
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

        // A notification card, swiped away with a finger
        NotificationCard {
            id: swipeCard
            y: 170
            width: 300
            notification: QtObject {
                property int id: 1
                property string appName: "Test"
                property string appIcon: ""
                property string summary: "A summary"
                property string body: "Some text in the body"
                property string image: ""
                property var actions: []
                property bool hasInlineReply: false
            }
            property int dismissals: 0
            onDismissRequested: dismissals++
        }

        // The interactions it reports, and the old signals beside them
        BarWidget {
            id: inputCell
            x: 60
            y: 330
            width: 100
            height: 40
            // What is bound, by interaction: only whether something is bound matters here
            property var bound: ({})
            bindingLookup: {
                const bound = inputCell.bound;
                return name => bound[name];
            }
            property var seen: []
            property int clicks: 0
            property int middleClicks: 0
            property var scrolls: []
            property var notches: []
            property var hovers: []
            onInteraction: (name, details) => {
                let entry = name;
                if (details.phase !== "")
                    entry += ":" + details.phase;
                if (details.amount !== 0)
                    entry += " " + (Math.round(details.amount * 100) / 100) + " " + details.direction;
                assert(details.byTouch === (name === "tap"), "the details of " + name + " say the pointer, a tap's the finger");
                seen.push(entry);
            }
            onClicked: clicks++
            onMiddleClicked: middleClicks++
            onScrolled: delta => scrolls.push(Math.round(delta * 100) / 100)
            onScrollNotch: direction => notches.push(direction)
            onHover: state => hovers.push(state)
        }

        WindowDriver {
            id: driver
            name: "PointerInputDriver"
        }
    }

    // Records what PopupWidget asks of its popup
    property QtObject _fakePopup: QtObject {
        id: fakePopup
        property bool active: false
        property string contentType: ""
        // The element that opened it, as Popup's own
        property Item openedBy: null
        property var calls: []

        function open(element, persistent, contentType, contentData, byTouch) {
            calls.push("open persistent=" + persistent + " byTouch=" + byTouch);
            fakePopup.active = true;
            fakePopup.contentType = contentType;
            fakePopup.openedBy = element;
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

    // Hover is passed on by a timer (BarWidget's _hoverSettle): on a busy machine it fires
    // later than any fixed wait, so a step that expects it waits for it (a hang guard, counted
    // in waits)
    function _until(condition, limitMs = 5000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    // A bound action, of no consequence: the cell only asks whether one is bound
    readonly property var _anything: ({ mode: "single", action: { action: "shell:popup.toggle" } })

    function _resetInput(bound = {}) {
        inputCell.bound = bound;
        inputCell.seen = [];
        inputCell.clicks = 0;
        inputCell.middleClicks = 0;
        inputCell.scrolls = [];
        inputCell.notches = [];
        inputCell.hovers = [];
    }

    function _seen() {
        return inputCell.seen.join(", ");
    }

    // The cell's interactions, each event QtTest can send. Hover first: the mouse is still
    // over the cell for every step after it, so it is entered once and left at the end.
    function _checkInteractions() {
        const cell = inputCell;
        const x = cell.width / 2;
        const y = cell.height / 2;
        _reset();
        _resetInput();

        driver.mouseMove(cell, x, y);
        _until(() => cell.seen.length > 0);
        assertEqual(_seen(), "hover:start", "the mouse coming over the cell is hover starting");
        assertEqual(cell.hovers.join(","), "true", "and the old hover signal, as before");

        // Nothing bound: every click is reported as it is released, nothing waits
        _resetInput();
        driver.mouseClick(cell, x, y, Qt.LeftButton);
        assertEqual(_seen(), "leftClick", "a left click, at once");
        driver.mouseClick(cell, x, y, Qt.MiddleButton);
        assertEqual(_seen(), "leftClick, middleClick", "a middle click");
        driver.mouseClick(cell, x, y, Qt.RightButton);
        assertEqual(_seen(), "leftClick, middleClick, rightClick", "a right click: the cell takes the right button");
        assertEqual(cell.clicks + "," + cell.middleClicks, "1,1", "the old clicked and middleClicked, once each: a right click is neither");
        _resetInput();
        driver.mouseClick(cell, x, y, Qt.LeftButton, Qt.ShiftModifier);
        driver.mouseClick(cell, x, y, Qt.LeftButton, Qt.ControlModifier);
        driver.mouseClick(cell, x, y, Qt.LeftButton, Qt.AltModifier);
        driver.mouseClick(cell, x, y, Qt.LeftButton, Qt.ShiftModifier | Qt.ControlModifier);
        assertEqual(_seen(), "shiftClick, ctrlClick, altClick, leftClick", "clicks with Shift, Ctrl, Alt; two modifiers: a left click, as before");
        assertEqual(cell.clicks, 4, "each still the old clicked, as before");
        driver.mouseClick(cell, x, y, Qt.MiddleButton, Qt.ShiftModifier);
        driver.mouseClick(cell, x, y, Qt.RightButton, Qt.ControlModifier);
        assertEqual(_seen(), "shiftClick, ctrlClick, altClick, leftClick, middleClick, rightClick", "a middle or right click ignores modifiers");
        _resetInput();
        driver.mouseDoubleClickSequence(cell, x, y);
        assertEqual(_seen(), "leftClick, leftClick", "no double click bound: a double click is two clicks, at once");
        assertEqual(cell.clicks, 2, "and two old clicks");

        // A double click bound: a plain click waits for a second one
        _resetInput({ doubleClick: _anything });
        driver.mouseDoubleClickSequence(cell, x, y);
        assertEqual(_seen(), "doubleClick", "a double click bound: one double click, no click");
        assertEqual(cell.clicks, 2, "the old clicked still fires for both, as before");
        _resetInput({ doubleClick: _anything });
        driver.mouseClick(cell, x, y);
        assertEqual(_seen(), "", "a single click waits for the double-click interval");
        assert(_until(() => cell.seen.length > 0), "and then comes");
        assertEqual(_seen(), "leftClick", "as a left click");
        assertEqual(cell.clicks, 1, "the old clicked at once, as before");
        _resetInput({ doubleClick: _anything });
        driver.mouseClick(cell, x, y);
        driver.mouseClick(cell, x, y, Qt.RightButton);
        assertEqual(_seen(), "leftClick, rightClick", "another click while one waits: the waiting one goes first");

        // A long press bound: the hold starts it, the release ends it and is no click
        _resetInput({ longPress: _anything });
        driver.mousePress(cell, x, y);
        assert(_until(() => cell.seen.length > 0), "the hold is reported while the button is down");
        assertEqual(_seen(), "longPress:start", "as a long press starting");
        driver.mouseRelease(cell, x, y);
        assertEqual(_seen(), "longPress:start, longPress:end", "the release ends it, and is no click");
        assertEqual(cell.clicks, 1, "the old clicked fires on the release, as before");
        // A press that moves away is a drag: no hold
        _resetInput({ longPress: _anything });
        driver.mousePress(cell, x, y);
        driver.mouseMove(cell, x + 30, y, -1, Qt.LeftButton);
        driver.mouseMove(cell, x + 31, y, -1, Qt.LeftButton);
        // A negative claim: the hold had its time and did not come
        driver.wait(Qt.styleHints.mousePressAndHoldInterval + 300);
        driver.mouseRelease(cell, x + 31, y);
        assertEqual(_seen(), "leftClick", "a press moved past the drag distance holds nothing: it is a click");
        // Held as long with no long press bound, or with the right button: a click
        _resetInput({ rightClick: _anything });
        driver.mousePress(cell, x, y);
        driver.wait(Qt.styleHints.mousePressAndHoldInterval + 300);
        driver.mouseRelease(cell, x, y);
        _resetInput({ longPress: _anything });
        driver.mousePress(cell, x, y, Qt.RightButton);
        driver.wait(Qt.styleHints.mousePressAndHoldInterval + 300);
        driver.mouseRelease(cell, x, y, Qt.RightButton);
        assertEqual(_seen(), "rightClick", "a held right button is its click: only the left one has a long press");

        // The wheel, nothing bound: each whole notch is a step
        _resetInput();
        driver.mouseWheel(cell, x, y, 0, 120);
        driver.mouseWheel(cell, x, y, 0, -120);
        driver.mouseWheel(cell, x, y, 0, 240);
        assertEqual(_seen(), "scrollUp 1 up, scrollDown -1 down, scrollUp 1 up, scrollUp 1 up",
                    "up, down, and an event of two notches is two steps");
        _resetInput();
        driver.mouseWheel(cell, x, y, 0, 60);
        assertEqual(_seen(), "", "half a notch is no step yet");
        driver.mouseWheel(cell, x, y, 0, 60);
        assertEqual(_seen(), "scrollUp 1 up", "the second half makes it");
        // (the old scrollNotch keeps its own remainder, which the two-notch event left at one)
        assertEqual(cell.scrolls.join(",") + " / " + cell.notches.join(","), "0.54,0.54 / 1,1",
                    "the old scrolled and scrollNotch, as before");
        // Qt's angleDelta.x is positive to the left (the compositor's own sign:
        // tests/lock/tests/cell-wheel.sh)
        _resetInput();
        driver.mouseWheel(cell, x, y, -120, 0);
        driver.mouseWheel(cell, x, y, 120, 0);
        assertEqual(_seen(), "scrollRight 1 right, scrollLeft -1 left", "the horizontal wheel: right, then left");
        assertEqual(cell.scrolls.join(",") + " / " + cell.notches.join(","), "0,0 / ",
                    "the old signals see no vertical movement in it, as before");
        // A continuous scroll bound: it takes the movement as measured, and the steps go
        _resetInput({ scroll: _anything, scrollSideways: _anything });
        driver.mouseWheel(cell, x, y, 0, 60);
        driver.mouseWheel(cell, x, y, 0, -224);
        driver.mouseWheel(cell, x, y, -56, 0);
        driver.mouseWheel(cell, x, y, 0, 0);
        assertEqual(_seen(), "scroll 0.54 up, scroll -2 down, scrollSideways 0.5 right",
                    "scroll and scrollSideways bound: one each per event, with the movement; an empty event is none");
        _resetInput({ scroll: _anything });
        driver.mouseWheel(cell, x, y, 120, 0);
        assertEqual(_seen(), "scrollLeft -1 left", "only the vertical one bound: the horizontal wheel still steps");

        // Hover ends as the mouse leaves
        _resetInput();
        driver.mouseMove(away, 5, 5);
        _until(() => cell.seen.length > 0);
        assertEqual(_seen(), "hover:end", "the mouse leaving the cell is hover ending");
        assertEqual(cell.hovers.join(","), "false", "and the old hover signal");

        // A finger's tap is a tap, by touch
        _resetInput();
        _tap(cell);
        assertEqual(_seen(), "tap", "a tap is reported as a tap, no pointer click");
        assertEqual(cell.clicks, 1, "and is still the old click");
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
        if (!driver.waitShown()) {
            fail("the window was never drawn");
            finish();
            return;
        }

        // --- the interactions a cell reports ---
        _checkInteractions();

        // --- the mouse: hover and click, as before ---
        _reset();
        driver.mouseMove(cell, 10, 10);
        _until(() => cell.hovers.length > 0);
        assertEqual(cell.hovers.join(","), "true", "the mouse coming over the cell is hover");
        driver.mouseMove(away, 5, 5);
        _until(() => cell.hovers.length > 1);
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
        popupCell.bindingLookup = InteractionRules.lookupFor({}, {}, true, "hover", []);
        driver.mouseMove(popupCell, 10, 10);
        _until(() => fakePopup.calls.length > 0);
        assertEqual(fakePopup.calls.join("; "), "open persistent=false byTouch=false",
                    "hover mode: the mouse over the cell opens it, to close when the mouse leaves");
        _reset();
        driver.mouseMove(popupCell, 10, 10);
        assert(_until(() => fakePopup.calls.length > 0), "hover mode: the mouse over the cell again opens it");
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
        popupCell.bindingLookup = InteractionRules.lookupFor({}, {}, true, "click", []);
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

        // --- a notification swiped away ---
        _reset();
        // Positions on the card's parent, which stays put: on the card itself every step would
        // go further, the card having moved with the finger
        const fixed = swipeCard.parent;
        const start = swipeCard.mapToItem(fixed, 60, 20);
        const swipe = (dx, steps) => {
            const touch = driver.touchEvent(fixed);
            touch.press(0, fixed, start.x, start.y).commit();
            for (let i = 1; i <= steps; i++) {
                driver.wait(30);
                touch.move(0, fixed, start.x + dx * i / steps, start.y).commit();
            }
            driver.wait(30);
            touch.release(0, fixed, start.x + dx, start.y).commit();
            driver.wait(Theme.duration("exit") + Theme.duration("move") + 120);
        };
        swipe(40, 8);
        assertEqual(swipeCard.dismissals, 0, "a short slow swipe: kept");
        assert(Math.abs(swipeCard.x) < 1 && swipeCard.opacity > 0.99, "and back in place");
        swipe(200, 10);
        assertEqual(swipeCard.dismissals, 1, "past a third of the card: dismissed");
        assert(swipeCard.swipedAway, "marked as swiped away, for the owner");
        assert(swipeCard.x > swipeCard.width, "gone out to the right");
        // A new notification brings it back
        swipeCard.notification = { id: 2, appName: "Test", summary: "Another", body: "", actions: [] };
        driver.wait(50);
        assert(Math.abs(swipeCard.x) < 1 && !swipeCard.swipedAway, "the next notification starts in place");
        driver.mousePress(fixed, start.x, start.y);
        driver.mouseMove(fixed, start.x + 200, start.y);
        driver.mouseRelease(fixed, start.x + 200, start.y);
        driver.wait(Theme.duration("exit") + 120);
        assertEqual(swipeCard.dismissals, 1, "a mouse drag dismisses nothing: it selects text");

        _reset();
        finish();
    }
}
