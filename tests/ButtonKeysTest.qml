import QtQuick
import Quickshell
import qs.components
import qs.singletons

// SmallButton and DeleteButton from the keyboard: Tab reaches them and a ring shows it, an
// unavailable one is passed over; Space, Return and the keypad's Enter click once, never
// reaching an owner that also handles Enter; an unavailable button
// does nothing; DeleteButton asks, deletes, and Escape cancels its question (and is the
// owner's otherwise); a click with the pointer leaves the keyboard with the field.
//
// Opens a small window for a moment, an ordinary one that takes the keyboard (keys are
// sent to it), in the runner's headless compositor.
TestCase {
    id: suite
    suiteName: "ButtonKeys"
    asynchronous: true
    // Its window takes the keyboard, as other suites' do
    ownProcess: true

    property int clicks: 0
    property int offClicks: 0
    property int confirms: 0
    property int asks: 0
    property int ownerEnters: 0
    property int ownerEscapes: 0

    property var _window: FloatingWindow {
        title: "h2s-tests button keys"
        visible: false
        implicitWidth: 520
        implicitHeight: 160
        color: Theme.popupBackground

        // An owner that handles Enter and Escape itself (a form, a popup)
        Item {
            id: area
            anchors.fill: parent
            Keys.onReturnPressed: suite.ownerEnters++
            Keys.onEnterPressed: suite.ownerEnters++
            Keys.onEscapePressed: suite.ownerEscapes++

            TextInput {
                id: field
                x: 10; y: 10
                width: 120
                height: 24
                text: "field"
                activeFocusOnTab: true
            }
            SmallButton {
                id: button
                x: 10; y: 50
                label: "Go"
                onClicked: suite.clicks++
            }
            SmallButton {
                id: off
                x: 80; y: 50
                label: "Off"
                available: false
                onClicked: suite.offClicks++
            }
            DeleteButton {
                id: remove
                x: 160; y: 50
                onConfirmed: suite.confirms++
                onAskingStarted: suite.asks++
            }
        }

        WindowDriver {
            id: driver
            name: "ButtonKeysDriver"
        }
    }

    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    // The ring a button draws inside itself while it has the keyboard
    function _ring(item) {
        for (const child of item.children)
            if (child instanceof Rectangle && child.color.a === 0 && child.anchors.margins === Theme.border.width)
                return child;
        return null;
    }

    function _tab(shift) {
        driver.keyClick(Qt.Key_Tab, shift ? Qt.ShiftModifier : Qt.NoModifier);
        driver.wait(20);
    }

    function runAsync() {
        try {
            _run();
        } finally {
            _window.visible = false;
        }
        finish();
    }

    function _run() {
        _window.visible = true;
        assert(_until(() => _window.visible && area.width > 0 && area.Window.active && driver.waitShown()), "the window shows and has the keyboard");
        field.forceActiveFocus();
        assert(field.activeFocus, "the field has the keyboard");
        const buttonRing = _ring(button);
        const removeRing = _ring(remove.children[0]);
        assert(buttonRing !== null && removeRing !== null, "both buttons have a ring");
        assert(!buttonRing.visible && !removeRing.visible, "… hidden without the keyboard");

        // --- Tab ---
        _tab();
        assert(button.activeFocus, "Tab from the field: the button");
        assert(buttonRing.visible && buttonRing.border.color === Theme.textSecondary, "… its ring shows, in the colour a focused checkbox takes");
        _tab();
        assert(!off.activeFocus && remove.activeFocus, "Tab again: past the unavailable button, to the delete button");
        assert(removeRing.visible && !buttonRing.visible, "… its ring shows, the other's hides");
        _tab(true);
        assert(button.activeFocus, "Shift+Tab: back to the button");

        // --- Space and Enter click ---
        driver.keyClick(Qt.Key_Space);
        assertEqual(clicks, 1, "Space clicks");
        driver.keyClick(Qt.Key_Return);
        assertEqual(clicks, 2, "Return clicks");
        driver.keyClick(Qt.Key_Enter, Qt.KeypadModifier);
        assertEqual(clicks, 3, "the keypad's Enter clicks");
        assertEqual(ownerEnters, 0, "… none reaches the owner, which handles Enter too");
        driver.keyClick(Qt.Key_A);
        assertEqual(clicks, 3, "another key: none");

        // --- an unavailable button ---
        off.forceActiveFocus();
        driver.keyClick(Qt.Key_Space);
        driver.keyClick(Qt.Key_Return);
        assertEqual(offClicks, 0, "unavailable, with the keyboard anyway: Space and Return do nothing");
        assertEqual(ownerEnters, 1, "… Return goes on to the owner");
        button.available = false;
        button.forceActiveFocus();
        driver.keyClick(Qt.Key_Space);
        assertEqual(clicks, 3, "a button made unavailable while it has the keyboard: no click");
        button.available = true;

        // --- DeleteButton ---
        remove.forceActiveFocus();
        driver.keyClick(Qt.Key_Escape);
        assertEqual(ownerEscapes, 1, "not asking, Escape is the owner's");
        driver.keyClick(Qt.Key_Space);
        assert(remove.asking && asks === 1 && confirms === 0, "Space: it asks");
        driver.keyClick(Qt.Key_Escape);
        assert(!remove.asking && confirms === 0, "Escape while asking: cancelled");
        assertEqual(ownerEscapes, 1, "… the owner does not see it");
        driver.keyClick(Qt.Key_Return);
        assert(remove.asking && asks === 2, "Return: it asks again");
        driver.keyClick(Qt.Key_Return);
        assert(!remove.asking && confirms === 1, "Return again: deleted, once");
        assertEqual(ownerEnters, 1, "… no Enter reached the owner");
        remove.available = false;
        driver.keyClick(Qt.Key_Space);
        assert(!remove.asking && asks === 2, "unavailable: Space does not ask");
        remove.available = true;

        // --- the pointer leaves the keyboard where it is ---
        field.forceActiveFocus();
        driver.mouseClick(button, button.width / 2, button.height / 2);
        assert(_until(() => clicks === 4), "a click clicks");
        assert(field.activeFocus && !buttonRing.visible, "… and the field keeps the keyboard");
        driver.mouseClick(remove.children[0], 10, remove.height / 2);
        assert(_until(() => remove.asking), "a click on the delete button asks");
        assert(field.activeFocus, "… the field keeps the keyboard");
        remove.asking = false;
    }
}
