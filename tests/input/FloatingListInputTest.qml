import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.singletons
import qs.tests

// components/Dropdown.qml and components/FloatingList.qml under a real pointer and keyboard
// (InputDriver): an open list stays attached to its dropdown while the page scrolls under a
// wheel and while its host moves, closes when the dropdown scrolls out of the page's view,
// takes the wheel over itself without scrolling the page; the keyboard opens, moves, picks,
// closes and types ahead, the focus staying on the dropdown; a hidden dropdown closes its
// list; groups show their titles and disabled entries are passed by keys and clicks.
TestCase {
    id: suite
    suiteName: "FloatingListInput"
    asynchronous: true

    property var pickedValues: []
    property var added: []

    readonly property var _many: Array.from({ length: 30 }, (_, i) => ({ value: "v" + i, label: "Item " + i }))

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 680
        implicitHeight: 320
        color: Theme.surface
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // A page that scrolls, as a settings page does
        Flickable {
            id: page
            x: 0; y: 0
            width: 200; height: 320
            clip: true
            contentHeight: 1200
            boundsBehavior: Flickable.StopAtBounds

            Item {
                id: before
                width: 10; height: 10
                activeFocusOnTab: true
            }
            Dropdown {
                id: plain
                x: 10; y: 60
                width: 160
                options: [{ value: "a", label: "Apple" }, { value: "b", label: "Banana" },
                          { value: "c", label: "Cherry" }, { value: "d", label: "Blueberry" }]
                value: "a"
                onPicked: value => { suite.pickedValues = suite.pickedValues.concat([value]); plain.value = value; }
            }
            Dropdown {
                id: long
                x: 10; y: 130
                width: 160
                options: suite._many
                value: "v0"
            }
            Dropdown {
                id: grouped
                x: 10; y: 190
                width: 160
                options: [{ value: "r", label: "Red", group: "Warm" }, { value: "o", label: "Orange", group: "Warm", disabled: true },
                          { value: "y", label: "Yellow", group: "Warm" }, { value: "b", label: "Blue", group: "Cold" }]
                value: "r"
                onPicked: value => grouped.value = value
            }
        }

        // An overlay host (a popup's panel) whose dropdown moves in it
        Rectangle {
            id: host
            objectName: "overlayHost"
            x: 220; y: 10
            width: 190; height: 300
            color: Theme.popupBackground
            Dropdown {
                id: hosted
                x: 10; y: 20
                width: 150
                options: [{ value: "x", label: "X" }, { value: "y", label: "Y" }]
                value: "x"
            }
        }

        // A "+ Add" picker (ReorderList's)
        ReorderList {
            id: reorder
            x: 430; y: 10
            width: 240
            items: ["one"]
            addOptions: ["two", "three"]
            onAdded: value => suite.added = suite.added.concat([value])
        }

        WindowDriver {
            id: driver
            name: "FloatingListInputDriver"
        }
        InputDriver {
            id: input
            driver: driver
        }
    }

    function _until(condition, limitMs = 5000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    function _listOf(dropdown) {
        const parentItem = dropdown === hosted ? host : dropdown.Window.window.contentItem;
        return Array.from(parentItem.children).find(child => child.floatingList === true && child.anchorItem === dropdown) ?? null;
    }

    function _attached(dropdown) {
        const list = _listOf(dropdown);
        if (!list || !list.visible)
            return false;
        const top = list.mapToItem(null, 0, 0);
        const below = dropdown.mapToItem(null, 0, dropdown.height);
        const above = dropdown.mapToItem(null, 0, 0);
        return Math.abs(top.x - below.x) < 1
            && (Math.abs(top.y - below.y - 2) < 1 || Math.abs(top.y + list.height + 2 - above.y) < 1);
    }

    // The rows of a dropdown's list, by their label
    function _rowOf(dropdown, label) {
        const list = _listOf(dropdown);
        const walk = item => {
            for (const child of item.children) {
                if (child.floatingEntry === true && child.floatingEntryText === label)
                    return child;
                const found = walk(child);
                if (found)
                    return found;
            }
            return null;
        };
        return list ? walk(list) : null;
    }

    function _current(dropdown) {
        return _listOf(dropdown)?.currentItem?.floatingEntryText ?? "";
    }

    function _close(dropdown) {
        dropdown.open = false;
        _until(() => !_listOf(dropdown)?.visible);
    }

    // The list follows its dropdown as the page scrolls under a real wheel, and closes when
    // the dropdown leaves the page's view
    function _attachment() {
        assert(input.click(plain, 20, plain.height / 2), "a click on the dropdown sent");
        assert(_until(() => plain.open && _listOf(plain)?.visible === true), "the click opens the list");
        assert(_attached(plain), "the list sits under the dropdown");
        // Beside the list, over the page
        assert(input.pointAt(page, 190, 300) && input.wheel(1), "a notch down over the page beside the list");
        assert(_until(() => page.contentY > 0), "the page scrolls (contentY " + page.contentY + ")");
        assert(_until(() => _attached(plain)), "the list stays attached to the dropdown as the page scrolls");
        assert(plain.open, "… and stays open");
        input.wheel(3);
        assert(_until(() => !plain.open), "the dropdown scrolled out of the page's view: its list closes (contentY " + page.contentY + ")");
        assert(!_listOf(plain).visible, "… and is not shown");
        page.contentY = 0;
        _until(() => plain.mapToItem(null, 0, 0).y > 50);

        // A host that moves carries its list along
        hosted.open = true;
        assert(_until(() => _attached(hosted)), "a dropdown in an overlay host: its list attached");
        hosted.y = 70;
        assert(_until(() => _attached(hosted)), "the dropdown moved in its host: the list moved with it");
        assert(_listOf(hosted).y > hosted.y, "… still under it");
        hosted.y = 262;
        assert(_until(() => _attached(hosted) && _listOf(hosted).y < hosted.y), "no room below: the list opens above the dropdown");
        _close(hosted);
        hosted.y = 20;
    }

    // The wheel over a long list scrolls the list, never the page under it
    function _ownWheel() {
        long.open = true;
        assert(_until(() => _listOf(long)?.visible === true && _attached(long)), "the long list open");
        const list = _listOf(long);
        assert(list.height <= 240 + 1, "it is no taller than its maximum (" + list.height + ")");
        const flick = list.children.find(child => child.contentY !== undefined);
        assert(input.pointAt(list, list.width / 2, list.height / 2) && input.wheel(2), "two notches over the list");
        assert(_until(() => flick.contentY > 0), "the list scrolls (" + flick.contentY + ")");
        assertEqual(page.contentY, 0, "… the page under it does not");
        // At its end the wheel still stays with the list
        input.wheel(30);
        assert(_until(() => flick.contentY >= flick.contentHeight - flick.height - 1), "scrolled to the list's end");
        input.wheel(2);
        driver.wait(50);
        assertEqual(page.contentY, 0, "a wheel past the list's end does not reach the page");
        _close(long);
    }

    // Keyboard: Tab to the dropdown, Space opens on the picked entry, Down/Up/End/Home move,
    // Enter picks, Escape closes with the focus kept, type-ahead by first letter
    function _keyboard() {
        before.forceActiveFocus();
        assert(input.key("Tab"), "Tab sent");
        assert(_until(() => plain.activeFocus), "Tab gives the dropdown the focus");
        assertEqual(plain.border.color.toString(), Theme.textSecondary.toString(), "… and shows its focus ring");
        input.key("space");
        assert(_until(() => plain.open && _listOf(plain)?.visible === true), "Space opens the list");
        assert(_until(() => _current(plain) === "Apple"), "… on the picked entry (" + _current(plain) + ")");
        input.key("Down");
        assert(_until(() => _current(plain) === "Banana"), "Down moves to the next (" + _current(plain) + ")");
        input.key("End");
        assert(_until(() => _current(plain) === "Blueberry"), "End to the last (" + _current(plain) + ")");
        input.key("Home");
        assert(_until(() => _current(plain) === "Apple"), "Home to the first (" + _current(plain) + ")");
        input.key("Down");
        input.key("Down");
        assert(_until(() => _current(plain) === "Cherry"), "Down twice (" + _current(plain) + ")");
        input.key("Return");
        assert(_until(() => !plain.open), "Enter closes the list");
        assertEqual(JSON.stringify(pickedValues), JSON.stringify(["c"]), "… and picks the entry");
        assert(plain.activeFocus, "the focus stays on the dropdown");

        input.key("Down");
        assert(_until(() => plain.open), "Down opens it too");
        assert(_until(() => _current(plain) === "Cherry"), "… on the picked entry (" + _current(plain) + ")");
        input.key("b");
        assert(_until(() => _current(plain) === "Blueberry"), "b: the next entry from b after it (" + _current(plain) + ")");
        input.key("b");
        assert(_until(() => _current(plain) === "Banana"), "b again: round to the first from b (" + _current(plain) + ")");
        input.key("Escape");
        assert(_until(() => !plain.open), "Escape closes the list");
        assertEqual(JSON.stringify(pickedValues), JSON.stringify(["c"]), "… picking nothing");
        assert(plain.activeFocus, "… and the focus is back on the dropdown");

        input.key("Return");
        assert(_until(() => plain.open), "Enter opens it");
        input.key("Tab");
        assert(_until(() => !plain.open), "Tab away closes it");
        assert(_until(() => long.activeFocus), "… and moves on");

        // The pages, on a list longer than its view
        input.key("space");
        assert(_until(() => long.open && _current(long) === "Item 0"), "the long list open on its first entry");
        input.key("Next");
        assert(_until(() => Number(_current(long).replace("Item ", "")) > 3), "Page Down moves a view's worth (" + _current(long) + ")");
        const list = _listOf(long);
        const row = list.currentItem;
        const rowTop = row.mapToItem(list, 0, 0).y;
        assert(rowTop >= 0 && rowTop + row.height <= list.height + 1, "… and scrolls it into view");
        input.key("Prior");
        assert(_until(() => _current(long) === "Item 0"), "Page Up back (" + _current(long) + ")");
        input.key("Escape");
        assert(_until(() => !long.open), "Escape closes it");
    }

    // A "+ Add" picker takes the keys as a dropdown does
    function _addPicker() {
        const find = item => {
            for (const child of item.children) {
                if (child.objectName === "addRow")
                    return child;
                const found = find(child);
                if (found)
                    return found;
            }
            return null;
        };
        const addRow = find(reorder);
        const picker = Array.from(addRow.Window.window.contentItem.children).find(child => child.floatingList === true && child.anchorItem === addRow);
        addRow.forceActiveFocus();
        input.key("Down");
        assert(_until(() => picker.visible), "Down on the add row opens its list");
        input.key("Down");
        assert(_until(() => picker.currentItem?.floatingEntryText === "two"), "Down: its first entry");
        input.key("Return");
        assert(_until(() => added.length === 1), "Enter adds it");
        assertEqual(JSON.stringify(added), JSON.stringify(["two"]), "… the entry the keys were on");
        input.key("space");
        assert(_until(() => picker.visible), "Space opens it again");
        input.key("Escape");
        assert(_until(() => !picker.visible), "Escape closes it");
        assert(addRow.activeFocus, "… the focus kept on the add row");
    }

    // A dropdown hidden while open closes its list and says so: back, it is closed
    function _closeOnHide() {
        plain.open = true;
        assert(_until(() => _listOf(plain)?.visible === true), "open");
        plain.visible = false;
        assert(_until(() => !plain.open), "hidden: the dropdown's list closed (open is false)");
        plain.visible = true;
        driver.wait(50);
        assert(!plain.open && !_listOf(plain).visible, "shown again: still closed");
        // The window hidden (the settings window hides rather than closing)
        plain.open = true;
        assert(_until(() => _listOf(plain)?.visible === true), "open again");
        _window.visible = false;
        assert(_until(() => !plain.open), "the window hidden: the list closed");
        _window.visible = true;
        const frames = driver.framesDrawn;
        assert(_until(() => driver.framesDrawn > frames), "the window shown again");
        assert(!plain.open && !_listOf(plain).visible, "… the list still closed");
    }

    // Groups and disabled entries
    function _groups() {
        grouped.forceActiveFocus();
        input.key("space");
        assert(_until(() => grouped.open && _listOf(grouped)?.visible === true), "the grouped list open");
        const list = _listOf(grouped);
        const titles = [];
        const walk = item => {
            for (const child of item.children) {
                if (child.floatingListHeader === true && child.visible)
                    titles.push(child.text);
                walk(child);
            }
        };
        walk(list);
        assertEqual(JSON.stringify(titles), JSON.stringify(["Warm", "Cold"]), "each group's title once, before its first entry");
        assert(_until(() => _current(grouped) === "Red"), "on the picked entry");
        input.key("Down");
        assert(_until(() => _current(grouped) === "Yellow"), "Down passes the disabled entry (" + _current(grouped) + ")");
        input.key("o");
        driver.wait(50);
        assertEqual(_current(grouped), "Yellow", "type-ahead passes it too");
        const orange = _rowOf(grouped, "Orange");
        assert(orange !== null && input.click(orange, orange.width / 2, orange.height / 2), "a click on the disabled entry");
        driver.wait(100);
        assert(grouped.open && grouped.value === "r", "picks nothing, the list stays open");
        const blue = _rowOf(grouped, "Blue");
        input.click(blue, blue.width / 2, blue.height / 2);
        assert(_until(() => !grouped.open && grouped.value === "b"), "a click on an entry picks it");
    }

    function runAsync() {
        assert(driver.waitShown(), "the window is shown");
        assert(input.pointAt(page, 5, 5), "the virtual pointer answers");
        _attachment();
        _ownWheel();
        _keyboard();
        _addPicker();
        _closeOnHide();
        _groups();
        finish();
    }
}
