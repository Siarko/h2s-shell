import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.panels.calendar
import qs.singletons
import qs.tests

// components/FocusRing.qml on every control of the mockup gallery that takes the keyboard,
// under a real pointer and keyboard (InputDriver): Tab to it (a text field: the owner's Tab
// handler moving the keyboard there) lights its ring, a click on it
// does not — whether the click gives it the focus or not — and a click on a control lit by
// Tab puts its ring out. A list's keys' entry wears the ring too. Every component in
// mockups/components/ is either checked here or named with why it is not (no control of its
// own, or not reached by the keyboard), so a new one cannot be left out.
TestCase {
    id: suite
    suiteName: "FocusRingInput"
    asynchronous: true

    // A suite to wait for first: one window at a time takes the keyboard
    property var after: null

    // Gallery components with no control of their own, or not reached by the keyboard
    readonly property var _notKeyboard: ({
        "detail-row": "selectable text, not reached by Tab",
        "floating-list": "a part of the dropdown: its keys' entry is checked with it",
        "heading": "text",
        "hint": "text",
        "hover-tip": "text",
        "notice": "text",
        "pill": "a bar cell, not reached by the keyboard",
        "schema-setting-editor": "made of the controls checked here",
        "section-title": "text",
        "settings-row": "a row the controls checked here sit in",
        "status-pill": "a bar cell, not reached by the keyboard",
        "switch-row": "its switch is not reached by the keyboard",
        "system-controlled-mark": "a mark shown beside a control; it takes no focus",
        "toggle-switch": "not reached by the keyboard"
    })

    // Each control after an item of its own that Tab starts from. A text field is not in
    // the Tab chain: its owner's keys bring the keyboard to it (as the event form's Tab does),
    // `next`
    component Before: Item {
        property var next: null
        width: 10
        height: 10
        activeFocusOnTab: true
        Keys.onTabPressed: event => {
            event.accepted = next !== null;
            if (next)
                next();
        }
    }

    property var _galleryNames: []
    property bool _listed: false
    property Process _list: Process {
        command: ["ls", "-1", Quickshell.shellDir + "/mockups/components"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { if (line.trim() !== "") suite._galleryNames = suite._galleryNames.concat([line.trim()]); }
        }
        onExited: suite._listed = true
    }

    // Shown only while this suite runs: the suites before it have windows of their own at
    // the same corner
    property bool _shown: false
    property var _window: PanelWindow {
        visible: suite._shown
        anchors { top: true; left: true }
        implicitWidth: 420
        implicitHeight: 640
        color: Theme.surface
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Column {
            x: 20
            y: 20
            spacing: 12

            Before { id: beforeButton }
            SmallButton { id: button; label: "Save" }
            Before { id: beforeDelete }
            DeleteButton { id: deleteButton }
            Before { id: beforeCheckbox }
            Checkbox { id: checkbox; label: "Remember" }
            Before { id: beforeDropdown }
            Dropdown {
                id: dropdown
                width: 160
                options: [{ value: "a", label: "Apple" }, { value: "b", label: "Banana" }]
                value: "a"
            }
            Before { id: beforeField; next: () => field.focusAll() }
            InputField { id: field; width: 160; placeholder: "Name" }
            Before { id: beforeDate; next: () => dateField.focusDay() }
            DateField { id: dateField; width: 160 }
            Before { id: beforeTime; next: () => timeField.focusHours() }
            TimeField { id: timeField; width: 100 }
            Before { id: beforeSlider }
            VolumeSlider { id: slider; width: 160; height: 20; value: 0.2; onMoved: volume => slider.value = volume }
        }

        WindowDriver {
            id: driver
            name: "FocusRingInputDriver"
        }
        InputDriver {
            id: input
            driver: driver
        }
    }

    // Each control checked: the gallery's name (or "" for one not in the gallery), the item
    // Tab starts from, where a click lands (in the control's coordinates)
    readonly property var _controls: [
        { name: "small-button", item: button, before: beforeButton },
        { name: "delete-button", item: deleteButton, before: beforeDelete },
        { name: "checkbox", item: checkbox, before: beforeCheckbox, at: () => Qt.point(7, 11) },
        { name: "dropdown", item: dropdown, before: beforeDropdown },
        { name: "input-field", item: field, before: beforeField },
        { name: "date-field", item: dateField, before: beforeDate },
        { name: "time-field", item: timeField, before: beforeTime },
        // The track far from the knob: the press is the slider's, not the knob's
        { name: "", item: slider, before: beforeSlider, at: () => Qt.point(slider.width * 0.9, slider.height / 2) }
    ]

    function _until(condition, limitMs = 5000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    function _rings(item) {
        const found = [];
        const walk = node => {
            for (const child of node.children) {
                if (child.focusRing === true)
                    found.push(child);
                walk(child);
            }
        };
        walk(item);
        return found;
    }

    function _lit(item) {
        return _rings(item).some(ring => ring.lit && ring.visible);
    }

    // The keyboard is in the control or in a part of it
    function _hasKeyboard(item) {
        for (let node = item.Window.activeFocusItem; node; node = node.parent) {
            if (node === item)
                return true;
        }
        return false;
    }

    function _reset(control) {
        dropdown.open = false;
        deleteButton.asking = false;
        control.before.forceActiveFocus();
        _until(() => control.before.activeFocus);
        // Moved off every control, so no hover is left
        input.pointAt(control.item.Window.window.contentItem, 400, 620);
    }

    function _check(control) {
        const label = control.name !== "" ? control.name : control.item.toString();
        const item = control.item;
        assert(_rings(item).length > 0, label + ": has a FocusRing");
        const at = control.at ? control.at() : Qt.point(item.width / 2, item.height / 2);

        // A click: whether it takes the keyboard or not, no ring
        _reset(control);
        assert(input.click(item, at.x, at.y), label + ": a click sent");
        driver.wait(100);
        assert(!_lit(item), label + ": no ring after a click (the keyboard " + (_hasKeyboard(item) ? "in it" : "elsewhere") + ")");

        // Tab: the ring
        _reset(control);
        assert(input.key("Tab"), label + ": Tab sent");
        assert(_until(() => _hasKeyboard(item)), label + ": Tab gives it the keyboard");
        assert(_until(() => _lit(item)), label + ": … and lights its ring");

        // A click on it then: the pointer took over, the ring goes out
        assert(input.click(item, at.x, at.y), label + ": a click on it sent");
        assert(_until(() => !_lit(item)), label + ": a click on it puts the ring out");

        // Tab away and back: lit again
        _reset(control);
        input.key("Tab");
        assert(_until(() => _lit(item)), label + ": Tab back to it lights it again");
        _reset(control);
    }

    // Another window that takes the keyboard while shown: this suite's window is no longer
    // active, as when the user clicks another app, and active again when it goes
    property bool _otherShown: false
    property var _other: PanelWindow {
        visible: suite._otherShown
        anchors { bottom: true; right: true }
        implicitWidth: 60
        implicitHeight: 60
        color: Theme.surface
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        Item { focus: true }
    }

    // The window hidden and shown again (a popup reopened, the Settings window shown again,
    // which keeps its page), or made inactive and active again: the focus comes back, and the
    // ring is as it was — out after a click (ordinary pointer use never shows it), lit after Tab
    function _returning() {
        const window = dropdown.Window.window;
        _reset(_controls[3]);
        assert(input.click(dropdown, dropdown.width / 2, dropdown.height / 2), "a click on the dropdown");
        assert(_until(() => dropdown.open && dropdown.activeFocus), "… opens it, the keyboard in it");
        dropdown.open = false;
        assert(_until(() => !dropdown.open) && !_lit(dropdown), "closed: the keyboard kept, no ring");

        _shown = false;
        assert(_until(() => !window.visible), "the window hidden");
        _shown = true;
        assert(driver.waitShown(), "… and shown again");
        assert(_until(() => dropdown.activeFocus), "the keyboard back in the dropdown");
        driver.wait(100);
        assert(!_lit(dropdown), "… still no ring");

        _otherShown = true;
        assert(_until(() => !dropdown.activeFocus), "another window takes the keyboard: the dropdown loses it");
        _otherShown = false;
        assert(_until(() => dropdown.activeFocus), "that window gone: the keyboard back in the dropdown");
        driver.wait(100);
        assert(!_lit(dropdown), "… still no ring");

        // Hidden with the keyboard in the dropdown, shown with it elsewhere (another page):
        // nothing kept for the next time Tab brings it there
        _shown = false;
        assert(_until(() => !window.visible), "hidden again");
        beforeButton.forceActiveFocus();
        _shown = true;
        assert(driver.waitShown() && _until(() => beforeButton.activeFocus), "shown with the keyboard elsewhere");
        _reset(_controls[3]);
        input.key("Tab");
        assert(_until(() => _lit(dropdown)), "Tab to the dropdown then: lit");

        // Lit by Tab, then the window made inactive and active again: as it was, lit
        _reset(_controls[3]);
        input.key("Tab");
        assert(_until(() => _lit(dropdown)), "Tab lights the dropdown's ring");
        _otherShown = true;
        assert(_until(() => !dropdown.activeFocus), "another window takes the keyboard");
        _otherShown = false;
        assert(_until(() => dropdown.activeFocus), "… and gives it back");
        driver.wait(100);
        assert(_lit(dropdown), "the focus came back with the window: lit as it was");
        input.key("Tab");
        input.key("Tab");
        assert(_until(() => _hasKeyboard(field)), "Tab on, past the next stop");
        // Not carried to the next time the dropdown is reached by the keyboard
        _reset(_controls[3]);
        input.key("Tab");
        assert(_until(() => _lit(dropdown)), "Tab to the dropdown later: lit again");
        _reset(_controls[3]);
    }

    // The dropdown's list: the keys' entry wears the ring, inside the entry
    function _listEntry() {
        _reset(_controls[3]);
        input.key("Tab");
        assert(_until(() => dropdown.activeFocus), "the dropdown has the keyboard");
        input.key("space");
        assert(_until(() => dropdown.open), "Space opens its list");
        const list = Array.from(dropdown.Window.window.contentItem.children).find(child => child.floatingList === true && child.anchorItem === dropdown);
        assert(_until(() => list?.currentItem), "the list has a keys' entry");
        const entryRings = () => _rings(list.currentItem).filter(ring => ring.lit && ring.visible);
        assert(_until(() => entryRings().length === 1), "the keys' entry wears the ring");
        assert(entryRings()[0]?.inside === true, "… inside the entry, which a list clips");
        input.key("Down");
        assert(_until(() => list.currentItem?.floatingEntryText === "Banana"), "Down moves the keys' entry");
        assert(_until(() => entryRings().length === 1), "… and the ring with it");
        input.key("Escape");
        assert(_until(() => !dropdown.open), "Escape closes the list");
    }

    function runAsync() {
        if (after)
            _until(() => after.done, 110000);
        _list.running = true;
        _shown = true;
        assert(driver.waitShown(), "the window is shown");
        assert(_until(() => _listed), "the gallery's components listed");
        assert(_galleryNames.length > 0, "… some (" + _galleryNames.length + ")");
        const checked = _controls.map(control => control.name).filter(name => name !== "");
        for (const name of _galleryNames)
            assert(checked.includes(name) || Object.prototype.hasOwnProperty.call(_notKeyboard, name),
                   "the gallery's " + name + " is checked here, or named with why it is not");
        for (const name of checked.concat(Object.keys(_notKeyboard)))
            assert(_galleryNames.includes(name), name + " is in the gallery");
        for (const control of _controls)
            _check(control);
        _listEntry();
        _returning();
        _shown = false;
        finish();
    }
}
