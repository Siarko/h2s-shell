import QtQuick
import qs.api
import qs.tests

// The old PrivilegedAction from a module whose manifest declares no `privileged`, in module
// test mode: refused before any prompt — blocked "undeclared", the reason in its status, its
// stand-in pkexec never started
TestCase {
    id: suite
    suiteName: "privileged-undeclared: PrivilegedAction refused"
    asynchronous: true

    readonly property var module: Api.moduleAt(Qt.resolvedUrl("."))
    readonly property string mark: (module?.dataDirectory ?? "") + "/pkexec-ran"
    property var _legacy: null
    property var _start: null
    property var _check: null

    property CommandRunner runner: CommandRunner {}

    property Timer _wait: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        property int stage: 0
        onTriggered: {
            waited += interval;
            if (stage === 0) {
                if ((suite._legacy === null || suite._start === null) && waited < 10000)
                    return;
                stage = 1;
                suite._afterAnswers();
            } else {
                if (suite._check === null && waited < 10000)
                    return;
                stop();
                suite._final();
                suite.finish();
            }
        }
    }

    function runAsync() {
        assert(Api.testMode, "test mode is on");
        assert(module.main !== null && module.dataDirectory !== "", "its main and its data directory are there");
        assertEqual(ModuleTestKit.status("privileged-undeclared")?.errors.length, 0, "no error before it asks");
        module.main.tryLegacy(mark, result => suite._legacy = result);
        module.privileged.start([module.programs["h2s-fixture-root"].path, "y"],
                                { what: "Try", timeoutMs: 5000, notifyFailures: false, done: result => suite._start = result });
        assert(ModuleTestKit.privilegedIdle, "nothing queued: no prompt can come");
        _wait.start();
    }

    function _afterAnswers() {
        const reason = "asks for administrator rights; module.json does not declare it (privileged)";
        assert(_legacy && !_legacy.ok && _legacy.blocked === "undeclared" && _legacy.error === reason && _legacy.code === -1 && !_legacy.dismissed && !_legacy.refused,
               "PrivilegedAction: blocked undeclared, said: " + JSON.stringify(_legacy));
        assert(_start && !_start.ok && _start.blocked === "undeclared" && _start.error === reason, "module.privileged.start: the same: " + JSON.stringify(_start));
        assertEqual(JSON.stringify(ModuleTestKit.status("privileged-undeclared")?.errors), JSON.stringify([reason]), "the reason in its status, once");
        assert(ModuleTestKit.privilegedIdle, "the queue idle");
        runner.start(["sh", "-c", "if [ -e \"$1\" ]; then echo ran; else echo never; fi", "sh", mark], { done: result => suite._check = result });
    }

    function _final() {
        assertEqual(String(_check?.stdout ?? "").trim(), "never", "its stand-in pkexec never ran");
    }
}
