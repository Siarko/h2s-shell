//@ pragma UseQApplication
import QtQuick
import Quickshell
import qs.singletons
import qs.tests
import qs.tests.input

// Run with: tests/run-input.sh (headless, with the lock bed's virtual pointer and keyboard on
// the compositor: H2S_INPUT_FIFO). The suites whose subject is input itself — a click, a
// wheel, a key as they arrive through a compositor — not in tests.qml, whose runner has no
// such devices. Each suite registers here once, one `property var _name: SomethingTest {}`
// line, and is named in _suites; all are asynchronous, and run one after another (one pointer, one keyboard).
QtObject {
    id: root

    // First: the suites use the real Config singleton, whose file is the user's
    readonly property bool _configReadOnly: { Config.readOnly = true; return true; }
    // First too: no reload when a file of the tree changes
    readonly property bool _noReload: { Quickshell.watchFiles = false; return true; }
    // Animations instant, so suites wait on states, not on them
    readonly property bool _instant: { Theme.instantAnimations = true; return true; }

    property var _floatingListInput: FloatingListInputTest {}
    property var _authPromptInput: AuthPromptInputTest { after: root._floatingListInput }
    property var _notificationScrollInput: NotificationScrollInputTest { after: root._authPromptInput }
    property var _focusRingInput: FocusRingInputTest { after: root._notificationScrollInput }
    // A new suite: its one line above this comment

    readonly property var _suites: [_floatingListInput, _authPromptInput, _notificationScrollInput, _focusRingInput]
    property var _modalAskInput: ModalAskInputTest { after: root._notificationScrollInput }
    // A new suite: its one line above this comment

    readonly property var _suites: [_floatingListInput, _authPromptInput, _notificationScrollInput, _modalAskInput]
    readonly property int _limitMs: 120000
    property int _waited: 0

    property var _clock: Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            root._waited += interval;
            const pending = root._suites.filter(suite => !suite.done);
            if (root._waited >= root._limitMs) {
                for (const suite of pending) {
                    suite.fail("timed out (" + root._limitMs / 1000 + " s)");
                    suite.finish();
                }
            }
            if (pending.some(suite => !suite.done))
                return;
            Qt.quit();
        }
    }
}
