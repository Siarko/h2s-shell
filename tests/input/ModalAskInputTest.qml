import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.singletons
import qs.tests
import qs.api as Api

// A module's question (ModalQuestions.ask, what module.ask calls) under real input
// (InputDriver): asked by a real click from a module's settings page and from its side panel
// in a stand-in Settings window, and from a real bar popup (panels/Popup.qml, the
// notification centre in it). Opened, nothing is focused; Tab goes left to right through the
// buttons, Shift+Tab back, Escape answers cancelled (over a side panel: the modal's, the
// panel stays); a click behind it does nothing. Over a popup the area below the bar takes
// the pointer and the keyboard: a click beside the modal keeps both, the popup stays open
// while the pointer is away and closes once answered. One question in the whole shell; the
// bar cell and the tray menu refuse; the popup closing, turning to another cell or going
// withdraws it (blocked "closed").
TestCase {
    id: suite
    suiteName: "ModalAskInput"
    asynchronous: true

    property var after: null
    property var _idle: WindowDriver {}
    property var driver: _idle
    property var input: null
    property var _window: null
    property var _bar: null
    property var _popup: null

    property var answers: []
    property int behindClicks: 0

    // A module's handle as ModalQuestions reads it
    property QtObject standIn: QtObject {
        property string moduleId: "fake"
        property bool active: true
    }

    readonly property var question: ({
        kind: "warning", title: "The name report-2026.pdf is taken", body: ["A file of that name is already in ~/Downloads:"],
        items: ["report-2026.pdf"],
        buttons: [{ id: "replace", label: "Replace", kind: "warning" }, { id: "keepBoth", label: "Keep both" }],
        cancelLabel: "Cancel", subject: { names: ["report-2026.pdf"] }
    })

    function remember(answer) {
        suite.answers = suite.answers.concat([answer]);
    }

    function ask(from) {
        return ModalQuestions.ask(standIn, from, question, remember);
    }

    // The stand-in Settings window: a module's page in its frame, with a button that asks and
    // a side panel whose content asks; the window's host the place of all of it
    property Component _windowComponent: Component { PanelWindow {
        id: settings
        readonly property var driver: windowDriver
        readonly property var input: inputDriver
        readonly property alias host: _host
        readonly property alias pageButton: _pageButton
        readonly property alias behind: _behind
        readonly property alias sidePanel: _sidePanel
        anchors { top: true; left: true }
        implicitWidth: 800
        implicitHeight: 560
        color: Theme.surface
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "h2s-tests"
        // The keyboard its own, as a focused normal window's
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Item {
            id: _content
            anchors.fill: parent
            ModulePageFrame {
                id: _frame
                anchors.fill: parent
                ColumnLayout {
                    spacing: 12
                    SmallButton {
                        id: _pageButton
                        objectName: "pageAsk"
                        label: "Log out"
                        onClicked: suite.ask(_pageButton)
                    }
                    SmallButton {
                        id: _behind
                        label: "Behind"
                        onClicked: suite.behindClicks++
                    }
                    Api.SidePanel {
                        id: _sidePanel
                        title: "Taildrop"
                        ColumnLayout {
                            SmallButton {
                                id: _panelAsk
                                objectName: "panelAsk"
                                label: "Save all"
                                onClicked: suite.ask(_panelAsk)
                            }
                        }
                    }
                }
            }
            SettingsModalHost {
                id: _host
                anchors.fill: parent
                placeRoot: _content
            }
        }

        WindowDriver {
            id: windowDriver
            name: "ModalAskInputDriver"
        }
        InputDriver {
            id: inputDriver
            driver: windowDriver
        }
    } }

    function _until(condition, limitMs = 5000) {
        for (let waited = 0; waited < limitMs && !condition(); waited += 10)
            driver.wait(10);
        return condition();
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

    function _focusName(host) {
        return host.Window.activeFocusItem?.objectName ?? "";
    }

    function _last() {
        return answers[answers.length - 1] ?? null;
    }

    function _shape(answer) {
        return answer ? [answer.button, answer.cancelled, answer.blocked].join(" ") : "none";
    }

    function _clickAt(item) {
        return input.click(item, item.width / 2, item.height / 2);
    }

    // Tab presses, the name of the item with the keyboard after each
    function _tabs(host, count, backwards) {
        const reached = [];
        for (let i = 0; i < count; i++) {
            const was = _focusName(host);
            input.key(backwards ? "ISO_Left_Tab" : "Tab");
            _until(() => _focusName(host) !== was, 2000);
            reached.push(_focusName(host));
        }
        return reached;
    }

    function runAsync() {
        if (after)
            _until(() => after.done, 110000);
        _window = _windowComponent.createObject(suite);
        driver = _window.driver;
        input = _window.input;
        try {
            if (!driver.waitShown()) {
                fail("the window was never drawn");
            } else {
                _settingsPage();
                _sidePanelQuestion();
                _popupQuestion();
            }
        } finally {
            if (_window.host.open)
                _window.host.cancel("window");
            Profiles.screenLocked = false;
            _popup?.destroy();
            _bar?.destroy();
            _window.destroy();
        }
        finish();
    }

    function _settingsPage() {
        const host = _window.host;
        answers = [];
        assert(_clickAt(_window.pageButton), "the page's button clicked");
        assert(_until(() => host.open && host.modal.panel.width > 0), "… its question opens over the window");
        assert(_until(() => host.modal._isInside(host.Window.activeFocusItem)), "… with the keyboard");
        assert(!_focusName(host).startsWith("modalButton:"), "… no button focused on opening");
        assertEqual(_tabs(host, 4).join(" "), "modalButton:0 modalButton:1 modalButton:2 modalButton:0",
                    "Tab: Replace, Keep both, Cancel, round again");
        const x = name => _find(host.modal, name).mapToItem(host.modal, 0, 0).x;
        assert(x("modalButton:0") < x("modalButton:1") && x("modalButton:1") < x("modalButton:2"), "… left to right");
        assertEqual(_tabs(host, 1, true).join(" "), "modalButton:2", "Shift+Tab: back to Cancel");

        assert(_clickAt(_window.behind), "a click on a button behind");
        driver.wait(100);
        assertEqual(behindClicks + " " + host.open, "0 true", "… does nothing, the question stays");

        assert(input.key("Escape"), "Escape");
        assert(_until(() => answers.length === 1), "… answered");
        assertEqual(_shape(_last()), "cancel true ", "… cancelled");

        assert(_clickAt(_window.pageButton), "asked again");
        assert(_until(() => host.open && _find(host.modal, "modalButton:1")?.width > 0), "… open");
        assert(_clickAt(_find(host.modal, "modalButton:1")), "Keep both clicked");
        assert(_until(() => answers.length === 2), "… answered");
        assertEqual(_shape(_last()) + " " + _last().subject.names[0], "keepBoth false  report-2026.pdf", "… Keep both, with the subject");
    }

    function _sidePanelQuestion() {
        const host = _window.host;
        _window.sidePanel.open = true;
        const panelButton = () => _find(_window.contentItem, "panelAsk");
        assert(_until(() => panelButton() !== null && panelButton().width > 0
                      && panelButton().mapToItem(null, 0, 0).x + panelButton().width < _window.width - 10), "the side panel opens");
        const before = answers.length;
        assert(_clickAt(panelButton()), "its content's button clicked");
        assert(_until(() => host.open), "… the question opens over the window and the side panel");
        // One question in the whole shell
        ask(_window.pageButton);
        assert(_until(() => answers.length === before + 1), "a second question meanwhile: answered");
        assertEqual(_shape(_last()), "cancel false busy", "… blocked \"busy\"");
        assert(_until(() => host.modal._isInside(host.Window.activeFocusItem)), "the first has the keyboard");
        assert(input.key("Escape"), "Escape");
        assert(_until(() => answers.length === before + 2), "… answers the question");
        assertEqual(_shape(_last()) + " " + _window.sidePanel.open, "cancel true  true", "… cancelled; the side panel stays open");
        _window.sidePanel.open = false;
    }

    function _popupQuestion() {
        _bar = Qt.createQmlObject("import QtQuick; import Quickshell; import Quickshell.Wayland; PanelWindow {"
            + " anchors { top: true; left: true } implicitWidth: 300; implicitHeight: 40; color: \"transparent\";"
            + " exclusionMode: ExclusionMode.Ignore; WlrLayershell.layer: WlrLayer.Overlay; WlrLayershell.namespace: \"h2s-tests\";"
            + " WlrLayershell.keyboardFocus: WlrKeyboardFocus.None; property alias cellA: cellA; property alias cellB: cellB;"
            + " Row { Item { id: cellA; width: 100; height: 40 } Item { id: cellB; width: 100; height: 40 } } }", suite);
        const component = Qt.createComponent(Qt.resolvedUrl("../../panels/Popup.qml"), Component.PreferSynchronous);
        _popup = component.createObject(suite, { popupPosition: 0, popupLength: 0, barScreen: _bar.screen ?? Quickshell.screens[0], barEdge: "top" });
        if (!_popup) {
            fail("the popup can be made (" + component.errorString() + ")");
            return;
        }
        _window.visible = false;

        // The bar cell: no place
        const before = answers.length;
        ask(_bar.cellA);
        assert(_until(() => answers.length === before + 1), "asked from a bar cell: answered");
        assertEqual(_shape(_last()), "cancel false place", "… blocked \"place\"");

        // The tray menu's popup takes none
        _popup.open(_bar.cellA, false, "tray-menu", null);
        assert(_until(() => _popup.item?.showPopup === true), "the tray menu's popup opens");
        const trayBody = _find(_popup.item.contentItem, "overlayHost");
        ask(trayBody);
        assert(_until(() => answers.length === before + 2), "asked from the tray menu: answered");
        assertEqual(_shape(_last()), "cancel false place", "… blocked \"place\"");
        _popup.active = false;

        // The notification centre's popup, the pointer away from it
        _popup.open(_bar.cellA, false, "notifications", null);
        assert(_until(() => _popup.item?.showPopup === true && _find(_popup.item.contentItem, "overlayHost")?.height > 0), "the centre's popup opens");
        const popupWindow = _popup.item;
        const body = _find(popupWindow.contentItem, "overlayHost");
        const host = ModalQuestions.hostAbove(body);
        ask(body);
        assert(host.open && _until(() => host.modal.panel.width > 0), "asked from the popup's content: open in the popup's host");
        assertEqual(host.modal.panel.width, Math.min(Theme.modal.widthSmall, host.width - 2 * Theme.modal.padding), "… at its usual width");
        assert(host.width >= popupWindow.width - 200 && host.height > body.height, "… over the area below the bar, not the popup alone");
        assert(host.objectName === "popupQuestion" && host.Window.window !== popupWindow, "… the popup's own, on a surface of its own");

        // Where the popup's window lies on the output: found by the pointer, over the dim
        const blocker = _find(host.modal, "modalBlocker");
        const screen = popupWindow.screen ?? Quickshell.screens[0];
        const probe = { x: 400, y: 450 };
        input.send("abs " + probe.x + " " + probe.y + " " + screen.width + " " + screen.height);
        assert(_until(() => blocker.containsMouse), "the pointer over the dim, away from the popup");
        const inBlocker = blocker.mapToItem(null, blocker.mouseX, blocker.mouseY);
        const offset = { x: probe.x - inBlocker.x, y: probe.y - inBlocker.y };
        const clickAt = (item, x, y) => {
            const point = item.mapToItem(null, x, y);
            return input.send("abs " + Math.round(point.x + offset.x) + " " + Math.round(point.y + offset.y) + " " + screen.width + " " + screen.height)
                && input.send("click left");
        };
        // A check that nothing happens: longer than the popup's hover close
        driver.wait(400);
        assert(_popup.active && !_popup.closing && host.open, "the pointer away: the popup stays open, the question too");
        assert(clickAt(blocker, blocker.width - 20, blocker.height - 20), "a click on the dim beside the modal");
        driver.wait(150);
        assert(_popup.active && !_popup.closing && host.open, "… keeps both");

        assert(_until(() => host.modal._isInside(host.Window.activeFocusItem)), "the modal has the keyboard");
        assert(!_focusName(host).startsWith("modalButton:"), "… no button focused");
        assertEqual(_tabs(host, 3).join(" "), "modalButton:0 modalButton:1 modalButton:2", "Tab with the pointer elsewhere: left to right");
        assertEqual(_tabs(host, 2, true).join(" "), "modalButton:1 modalButton:0", "… Shift+Tab back");
        const counted = answers.length;
        assert(input.key("space"), "Space on Replace");
        assert(_until(() => answers.length === counted + 1), "… answered");
        assertEqual(_shape(_last()), "replace false ", "… Replace");
        assert(_until(() => !_popup.active || _popup.closing), "answered with the pointer away: the popup closes");
        assert(_until(() => !_popup.active), "… and goes");

        // A real click on a button; then withdrawn by the popup closing, another cell, going
        _popup.open(_bar.cellA, true, "notifications", null);
        assert(_until(() => _popup.item?.showPopup === true), "opened again (by a click: it stays)");
        const shown = ModalQuestions.hostAbove(_find(_popup.item.contentItem, "overlayHost"));
        ask(_find(_popup.item.contentItem, "overlayHost"));
        assert(_until(() => _find(shown.modal, "modalButton:1")?.width > 0), "asked");
        // Its surface on screen: the pointer over its dim reaches it
        const shownBlocker = _find(shown.modal, "modalBlocker");
        input.send("abs " + (probe.x + 5) + " " + probe.y + " " + screen.width + " " + screen.height);
        assert(_until(() => shownBlocker.containsMouse), "… its surface takes the pointer");
        assert(clickAt(_find(shown.modal, "modalButton:1"), 10, 5), "Keep both clicked");
        assert(_until(() => answers.length === counted + 2), "… answered");
        assertEqual(_shape(_last()), "keepBoth false ", "… Keep both");
        assert(_popup.active && !_popup.closing, "… the popup opened by a click stays");

        ask(_find(_popup.item.contentItem, "overlayHost"));
        _popup.open(_bar.cellB, true, "notifications", null);
        assertEqual(_shape(_last()), "cancel false closed", "opened from another cell: withdrawn, blocked \"closed\"");
        ask(_find(_popup.item.contentItem, "overlayHost"));
        _popup.close();
        assertEqual(_shape(_last()), "cancel false closed", "the popup closing: blocked \"closed\"");
        assert(_until(() => !_popup.active), "… it goes");
        _popup.open(_bar.cellA, true, "notifications", null);
        assert(_until(() => _popup.item?.showPopup === true), "opened again");
        const beforeGone = answers.length;
        ask(_find(_popup.item.contentItem, "overlayHost"));
        _popup.active = false;
        assert(_until(() => answers.length === beforeGone + 1), "the popup destroyed while asking: answered");
        assertEqual(_shape(_last()) + " " + ModalQuestions.busy, "cancel false closed false", "… blocked \"closed\", the shell free");

        // The lock
        _popup.open(_bar.cellA, true, "notifications", null);
        assert(_until(() => _popup.item?.showPopup === true), "opened again");
        Profiles.screenLocked = true;
        const beforeLock = answers.length;
        ask(_find(_popup.item.contentItem, "overlayHost"));
        assert(_until(() => answers.length === beforeLock + 1), "asked while locked: answered");
        assertEqual(_shape(_last()), "cancel false locked", "… blocked \"locked\"");
        Profiles.screenLocked = false;
        _popup.active = false;
    }
}
