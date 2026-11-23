//@ pragma UseQApplication
import QtQuick
import Quickshell
import qs.singletons
import qs.tests.helper

// Run with: tests/run-helper.sh (headless, on its private bus, with the helper it built:
// H2S_TEST_HELPER, H2S_TEST_CLIENT). The suites that run the shell's side of the helper
// against the real program; not in tests.qml, which has no helper and no bus.
QtObject {
    id: root

    // First: the suites use the real Config singleton, whose file is the user's
    readonly property bool _configReadOnly: { Config.readOnly = true; return true; }
    // First too: no reload when a file of the tree changes (Quickshell watches the files it
    // loaded by default). A reload in the middle of a run starts every suite again in a new
    // generation while the old one's timers still fire: a shard reports its suites twice or
    // crashes, whenever the tree is edited while the tests run.
    readonly property bool _noReload: { Quickshell.watchFiles = false; return true; }

    readonly property var _suites: [_screenSaverClient, _idleService]
    property var _screenSaverClient: ScreenSaverClientTest {}
    property var _idleService: IdleServiceTest { after: root._screenSaverClient }

    readonly property int _limitMs: 60000
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
