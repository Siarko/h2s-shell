import QtQuick
import Quickshell
import qs.api
import qs.tests

// The fixture's settings page in the test kit's page frame (API 1.34, ModuleTestKit.pageFrame):
// the button at the end of its heading opens its SidePanel, its content built in the frame;
// the session locking closes it (ModuleTestKit.setSessionLocked), and so does the frame going.
// (1.44) A question asked from the panel's content (module.ask) shows over the frame: answered
// through the kit as the user would (ModuleTestKit.question, answerQuestion, cancelQuestion),
// and withdrawn, blocked "closed", when the frame goes.
// It runs beside the fixture's other suites: the lock is set and lifted in one step.
TestCase {
    id: suite
    suiteName: "good: the side panel"
    asynchronous: true

    readonly property var module: Api.moduleAt(Qt.resolvedUrl("."))
    property var _reasons: []
    property var _answers: []
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
            assertEqual(typeof module.ask, "function", "module.ask (1.44)");
            const remember = answer => suite._answers = suite._answers.concat([answer]);
            const question = { kind: "warning", title: "Replace report.pdf?", body: ["A file of that name is there."],
                items: ["report.pdf"], checks: [{ key: "all", label: "For all" }],
                buttons: [{ id: "replace", label: "Replace", kind: "warning" }, { id: "keepBoth", label: "Keep both" }],
                subject: { names: ["report.pdf"] } };
            const call = module.ask(_content(), question, remember);
            assert(call.open && ModuleTestKit.questionOpen, "asked from the side panel's content: open over the frame");
            assertEqual(JSON.stringify(ModuleTestKit.question), JSON.stringify({ moduleId: "good", kind: "warning", title: "Replace report.pdf?",
                body: ["A file of that name is there."], items: ["report.pdf"], checks: ["all"],
                buttons: [{ id: "replace", label: "Replace", kind: "warning" }, { id: "keepBoth", label: "Keep both", kind: "normal" },
                          { id: "cancel", label: "Cancel", kind: "cancel" }] }), "… as shown: ModuleTestKit.question");
            assertEqual(ModuleTestKit.answerQuestion("good", "nope"), "the question has no button \"nope\"", "answerQuestion: no such button");
            assertEqual(ModuleTestKit.answerQuestion("other", "replace"), "the open question is module \"good\"'s, not \"other\"", "… another module's");
            assertEqual(ModuleTestKit.answerQuestion("good", "keepBoth", { all: true }), "", "… Keep both, For all ticked");
            const answer = _answers[0];
            assertEqual([answer?.button, answer?.cancelled, answer?.blocked, answer?.values?.all, answer?.subject?.names?.[0]].join(" "),
                        "keepBoth false  true report.pdf", "… answered with the button, the checkbox and the subject");
            assert(!call.open && !ModuleTestKit.questionOpen, "… closed");
            module.ask(_content(), question, remember);
            assertEqual(ModuleTestKit.cancelQuestion("good"), "", "cancelQuestion");
            assertEqual(_answers[1]?.cancelled + " " + _answers[1]?.blocked, "true ", "… cancelled");
            module.ask(_content(), question, remember);
            _frame.destroy();
        });
        _then("the frame destroyed", () => _reasons.length === 2, () => {
            assertEqual(_reasons.join(","), "lock,page", "the frame going: closed(\"page\")");
            assertEqual(_answers[2]?.button + " " + _answers[2]?.cancelled + " " + _answers[2]?.blocked, "cancel false closed",
                        "… and its open question withdrawn: blocked \"closed\"");
            assert(!ModuleTestKit.questionOpen, "… none open");
        });
        _clock.start();
    }
}
