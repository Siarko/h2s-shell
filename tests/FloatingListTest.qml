import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.singletons

// components/FloatingList.qml and the Dropdown built on it, in a window: an open list and
// its press catcher live in the window's top item, so they follow whether the anchor is
// shown — a page hidden while its list is open leaves neither over the window, a press
// there reaches what is under it; the hidden anchor tells the owner the list closed, so a
// dropdown comes back closed, and a list held open by a binding (as a plan's scene holds a
// menu open) is back when the page is shown again.
TestCase {
    id: suite
    suiteName: "FloatingList"
    asynchronous: true

    property int closes: 0
    property int clicks: 0

    property var _window: PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 300
        implicitHeight: 240
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // The page with an open list: its anchor, a dropdown open, and a list held open
        Item {
            id: page
            anchors.fill: parent
            Rectangle {
                id: anchor
                x: 10; y: 10
                width: 120; height: 24
                color: Theme.surface
            }
            FloatingList {
                id: list
                anchorItem: anchor
                open: true
                onClosed: suite.closes++
                Text { text: "An option" }
            }
            Dropdown {
                id: dropdown
                x: 160; y: 10
                width: 120
                options: [{ value: "a", label: "A" }, { value: "b", label: "B" }]
                value: "a"
            }
        }

        // What is under it once the page is hidden
        Rectangle {
            id: below
            x: 10; y: 120
            width: 120; height: 40
            visible: !page.visible
            color: Theme.surface
            MouseArea {
                anchors.fill: parent
                onClicked: suite.clicks++
            }
        }

        WindowDriver {
            id: driver
            name: "FloatingListDriver"
        }
    }

    function _until(condition, limitMs = 3000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
    }

    // The window's top items that are floating lists, and the press catchers (MouseAreas
    // filling the top item, which only the lists put there)
    function _top() {
        return Array.from(anchor.Window.window.contentItem.children);
    }
    function _lists() {
        return _top().filter(child => child.floatingList === true);
    }
    function _catchers() {
        return _top().filter(child => child.toString().startsWith("QQuickMouseArea"));
    }

    function runAsync() {
        assert(driver.waitShown(), "the window is shown");
        dropdown.open = true;
        const dropdownList = () => _lists().find(child => child !== list);
        assert(_until(() => list.visible && dropdownList()?.visible === true), "shown: the held list and the dropdown's list are open");
        assertEqual(_catchers().filter(catcher => catcher.visible).length, 2, "… each with its press catcher");

        page.visible = false;
        assert(_until(() => below.visible), "the page hidden");
        assert(!list.visible && !dropdownList().visible, "hidden: neither list is shown");
        assert(!dropdown.open, "… the dropdown's list closed (its anchor hid)");
        assert(list.open, "… the list held open by its binding still open");
        assertEqual(closes, 1, "… and told it closed");
        assertEqual(_catchers().filter(catcher => catcher.visible).length, 0, "… no press catcher shown");
        driver.mouseClick(below, below.width / 2, below.height / 2);
        assertEqual(clicks, 1, "a press where the catchers were reaches the item under them");
        assertEqual(closes, 1, "… and closes nothing");

        page.visible = true;
        assert(_until(() => list.visible), "the page shown again: the held list is back");
        assert(!dropdown.open && !dropdownList().visible, "… the dropdown's list is not");
        assertEqual(_catchers().filter(catcher => catcher.visible).length, 1, "… one press catcher, the held list's");
        driver.mouseClick(anchor, 5, 5);
        assertEqual(closes, 2, "a press beside the held list closes it");
        finish();
    }
}
