import QtQuick
import Quickshell
import qs.api
import qs.tests

// The fixture's settings page in the test kit's page frame (API 1.34, ModuleTestKit.pageFrame):
// the button at the end of its heading opens its SidePanel, its content built in the frame;
// the session locking closes it (ModuleTestKit.setSessionLocked), and so does the frame going.
// It runs beside the fixture's other suites: the lock is set and lifted in one step.
TestCase {
    id: suite
    suiteName: "good: the side panel"
    asynchronous: true

    readonly property var module: Api.moduleAt(Qt.resolvedUrl("."))
    property var _reasons: []
    property var _frame: null
    property var _page: null
    property var _steps: []

    property var _window: FloatingWindow {
        title: "good fixture page"
        implicitWidth: 600
        implicitHeight: 400
        color: Api.theme.popupBackground
    }

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite._window.visible = false;
                suite.finish();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {}
            if (!ready && waited < 8000)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
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

    function _makePage() {
        _frame = ModuleTestKit.pageFrame.createObject(_window.contentItem, { width: 600, height: 400 });
        const component = Qt.createComponent(Qt.resolvedUrl("../GoodSettings.qml"), Component.PreferSynchronous);
        _page = component.createObject(_frame.body, { module: module });
        _find(_page, "goodDetailsPanel").closed.connect(reason => suite._reasons = suite._reasons.concat([reason]));
    }

    function _content() {
        return _find(_frame, "goodDetails");
    }

    function runAsync() {
        _then("the window shows", () => _window.visible && _window.contentItem.width > 0, () => {
            _makePage();
            assert(_frame !== null && _page !== null, "the page in the kit's frame");
            assertEqual(_content(), null, "the panel's content does not exist while it is closed");
            _find(_page, "goodDetailsButton").clicked();
        });
        // The lock is the whole module host's (runs as administrator, the file chooser): it is
        // set and lifted in one go, while the fixture's other suites have none of those open
        _then("the panel opens (no run as administrator, no chooser open)",
              () => _content() !== null && ModuleTestKit.privilegedIdle && !ModuleTestKit.chooserOpen, () => {
            const panel = _find(_page, "goodDetailsPanel");
            assertEqual(panel.open, true, "the button at the heading's end opened it");
            assert(_content().width > 0 && _content().width < 600, "its content laid out in the panel, narrower than the page");
            ModuleTestKit.setSessionLocked(true);
            assertEqual(_reasons.join(","), "lock", "the session locked: closed(\"lock\")");
            assertEqual(panel.open, false, "… open set false");
            panel.open = true;
            assertEqual(panel.open, false, "… and while locked it does not open");
            ModuleTestKit.setSessionLocked(false);
        });
        _then("its content goes once it has closed", () => _content() === null, () => {
            _find(_page, "goodDetailsButton").clicked();
        });
        _then("open again", () => _content() !== null, () => {
            _frame.destroy();
        });
        _then("the frame destroyed", () => _reasons.length === 2, () => {
            assertEqual(_reasons.join(","), "lock,page", "the frame going: closed(\"page\")");
        });
        _clock.start();
    }
}
