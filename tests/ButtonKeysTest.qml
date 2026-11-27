import QtQuick
import Quickshell
import qs.components
import qs.singletons

// SmallButton and DeleteButton from the keyboard: Tab reaches them and a ring shows it, an
// unavailable one is passed over; Space, Return and the keypad's Enter click once, never
// reaching an owner that also handles Enter; an unavailable button
// does nothing; DeleteButton asks, deletes, and Escape cancels its question (and is the
// owner's otherwise); a click with the pointer leaves the keyboard with the field. A
// repeated key (held down) does nothing more, on fake events. FocusTrap keeps Tab inside
// its scope only while the keyboard is there; an open SideDrawer keeps Tab inside, and
// Escape on its asking DeleteButton cancels the question before closing the panel;
// FocusFollower scrolls the item with the keyboard into view (ApiElementRules.scrollToShow).
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
    property var drawerEvents: []

    property var _window: FloatingWindow {
        title: "h2s-tests button keys"
        visible: false
        implicitWidth: 700
        implicitHeight: 400
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

        // A scope that keeps Tab, two buttons in it and one after it
        Row {
            id: trapScope
            x: 10; y: 120
            spacing: 10
            SmallButton { id: trapA; objectName: "trapA"; label: "A" }
            SmallButton { id: trapB; objectName: "trapB"; label: "B" }
        }
        SmallButton { id: afterTrap; objectName: "afterTrap"; x: 10; y: 160; label: "After" }
        FocusTrap { scope: trapScope; active: true }

        // A view scrolled to its top, a button far below in it
        Flickable {
            id: view
            x: 400; y: 120
            width: 200; height: 100
            contentWidth: width
            contentHeight: 600
            clip: true
            SmallButton { id: far; y: 500; label: "Far" }
        }
        FocusFollower {}

        SideDrawer {
            id: drawer
            anchors.fill: parent
            title: "Drawer"
            content: Component {
                Column {
                    spacing: 6
                    SmallButton { objectName: "drawerButton"; label: "In" }
                    DeleteButton { objectName: "drawerDelete" }
                }
            }
            onRequested: event => {
                suite.drawerEvents = suite.drawerEvents.concat([event]);
                drawer.open = false;
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

    // The keyboard's ring of a button (FocusRing), drawn while `visible` here
    function _ring(item) {
        for (const child of item.children)
            if (child.focusRing === true)
                return { get visible() { return child.lit; }, get border() { return child.children[0].border; } };
        return null;
    }

    function _tab(shift) {
        driver.keyClick(Qt.Key_Tab, shift ? Qt.ShiftModifier : Qt.NoModifier);
        driver.wait(20);
    }

    function _find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (const child of item.children) {
            const found = _find(child, name);
            if (found)
                return found;
        }
        return null;
    }

    function _event(key, repeat) {
        return { key: key, isAutoRepeat: repeat === true, accepted: false };
    }

    function _held() {
        // A key held down: the first press, then the repeats the keyboard sends
        const counted = { clicks: 0 };
        const probe = Qt.createQmlObject('import qs.components; SmallButton {}', area);
        probe.clicked.connect(() => counted.clicks++);
        const first = _event(Qt.Key_Space);
        probe._key(first);
        const repeat = _event(Qt.Key_Space, true);
        probe._key(repeat);
        assertEqual(counted.clicks + " " + first.accepted + " " + repeat.accepted, "1 true true", "SmallButton: a held Space clicks once, each event taken");
        probe.destroy();

        const asker = Qt.createQmlObject('import qs.components; DeleteButton {}', area);
        let confirmed = 0;
        asker.confirmed.connect(() => confirmed++);
        asker._key(_event(Qt.Key_Return));
        const again = _event(Qt.Key_Return, true);
        asker._key(again);
        assertEqual(asker.asking + " " + confirmed + " " + again.accepted, "true 0 true", "DeleteButton: a held Return asks and does not go on to delete");
        const override = _event(Qt.Key_Escape);
        asker._override(override);
        assert(override.accepted, "… asking, it takes Escape before any shortcut");
        asker.asking = false;
        const notAsking = _event(Qt.Key_Escape);
        asker._override(notAsking);
        assert(!notAsking.accepted, "… not asking, it leaves Escape to shortcuts");
        asker.destroy();
    }

    function _rules() {
        const show = ApiElementRules.scrollToShow;
        assertEqual(show(20, 40, 0, 100, 600, 8), 0, "scrollToShow: in view, the view stays");
        assertEqual(show(500, 530, 0, 100, 600, 8), 438, "… below: just enough to show it, the margin under it");
        assertEqual(show(50, 70, 200, 100, 600, 8), 42, "… above: its top, the margin above it");
        assertEqual(show(100, 400, 0, 100, 600, 8), 92, "… taller than the view: its top shows");
        assertEqual(show(580, 600, 0, 100, 600, 8), 500, "… never past the content's end");
        assertEqual(show(2, 20, 50, 100, 600, 8), 0, "… nor above its start");
        assertEqual(show(500, 530, 30, 0, 600, 8) + " " + show(NaN, 530, 30, 100, 600, 8), "30 30", "… no view or a value not a number: stays");
    }

    function runAsync() {
        try {
            _rules();
            _held();
            _run();
            _traps();
        } finally {
            drawer.open = false;
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
        assert(buttonRing.visible && buttonRing.border.color === Theme.focusRing, "… its ring shows, in the theme's keyboard colour");
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

    function _traps() {
        // --- FocusTrap ---
        afterTrap.forceActiveFocus();
        _tab(true);
        assert(!afterTrap.activeFocus, "the keyboard outside the trap's scope: Shift+Tab goes on as usual");
        trapA.forceActiveFocus();
        const reached = [];
        for (let i = 0; i < 3; i++) {
            _tab();
            reached.push(area.Window.activeFocusItem?.objectName ?? "");
        }
        assertEqual(reached.join(" "), "trapB trapA trapB", "inside the scope: Tab cycles there, never reaching the button after it");
        _tab(true);
        assertEqual(area.Window.activeFocusItem?.objectName, "trapA", "… Shift+Tab too");

        // --- FocusFollower ---
        assertEqual(view.contentY, 0, "the view at its top, the button below out of sight");
        far.forceActiveFocus();
        assert(_until(() => view.contentY > 0), "the button takes the keyboard: the view scrolls");
        const place = far.mapToItem(view, 0, 0);
        assert(place.y >= 0 && place.y + far.height <= view.height, "… until it shows whole (" + place.y + ")");

        // --- an open side panel ---
        field.forceActiveFocus();
        drawer.open = true;
        assert(_until(() => _find(drawer, "drawerDelete") !== null && drawer.panel.x < area.width), "the side panel opens");
        const inside = [];
        let stayed = true;
        for (let i = 0; i < 6; i++) {
            _tab();
            const focused = area.Window.activeFocusItem;
            stayed = stayed && drawer._isInside(focused);
            inside.push(focused?.objectName || focused?.label || "");
        }
        assert(stayed, "Tab six times in an open side panel: the keyboard never leaves it (" + inside.join(", ") + ")");
        assert(inside.includes("drawerButton") && inside.includes("drawerDelete") && inside.includes("Close"), "… it reaches each of its buttons");
        _tab(true);
        assert(drawer._isInside(area.Window.activeFocusItem), "… nor with Shift+Tab");

        const asker = _find(drawer, "drawerDelete");
        asker.forceActiveFocus();
        driver.keyClick(Qt.Key_Space);
        assert(asker.asking, "its delete button asks");
        driver.keyClick(Qt.Key_Escape);
        assert(!asker.asking && drawer.open && drawerEvents.length === 0, "Escape: the question cancelled, the panel stays open");
        driver.keyClick(Qt.Key_Escape);
        assert(_until(() => !drawer.open) && drawerEvents.join(",") === "escape", "Escape again: the panel asked to close");
        assert(_until(() => field.activeFocus), "… and the keyboard back with the field");
    }
}
