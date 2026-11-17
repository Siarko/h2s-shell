//@ pragma UseQApplication
import QtQuick
import Quickshell
import qs.singletons
import qs.tests

// Run with: tests/run-modules.sh <module dir>… (headless, as tests/run-unit.sh runs
// tests.qml). Loads the modules named in H2S_TEST_MODULES (canonical, colon-separated) with
// the shell's own module host (the Modules singleton's, so the core's registries see the
// modules as in the shell) — exactly as the shell loads them — then creates each loaded module's suites (its
// manifest's "tests") by URL. A module that did not load, one that lists no suites and a
// suite that does not compile are FAILs. With H2S_TEST_MODULE_SUITES (suite file names without
// ".qml", colon-separated: tests/run-modules.sh --suite) only those suites are created; a
// name that no module lists, all of them loaded, is printed as MODULE-SUITES-UNKNOWN and
// nothing is created. Imports qs.tests so that Quickshell makes the
// TestCase type available to the modules' suites (they are loaded by URL).
QtObject {
    id: root

    // First: the suites use the real Config singleton, whose file is the user's
    readonly property bool _configReadOnly: { Config.readOnly = true; return true; }

    // The shell's host: a module's suites see the registries, handles and slots as they are in
    // the shell (its environment gave it no module: H2S_SHELL_MODULES is not set here)
    readonly property var host: Modules.host
    property var _suites: []
    property string _phase: "loading"
    property int _waited: 0

    function _settled() {
        return host.statuses.length > 0 && !host.statuses.some(status => status.state === "pending");
    }

    function _fail(message) {
        console.error("  FAIL: " + message);
    }

    // A suite's name for the selection: its file without the directory and ".qml"
    function suiteNameOf(file) {
        return String(file).replace(/^.*\//, "").replace(/\.qml$/, "");
    }

    function _runSuites() {
        console.log("\n=== modules ===");
        const value = Quickshell.env("H2S_TEST_MODULE_SUITES");
        const selected = typeof value === "string" && value !== "" ? value.split(":") : [];
        let runnable = [];
        for (const status of host.statuses) {
            const label = (status.id || "?") + " (" + status.directory + ")";
            if (status.state !== "loaded") {
                _fail("module " + label + " did not load: " + status.state
                      + (status.errors.length > 0 ? " — " + status.errors.join("; ") : ""));
                continue;
            }
            console.log("  module " + label + " " + status.version + ": loaded"
                        + (status.warnings.length > 0 ? " (warnings: " + status.warnings.join("; ") + ")" : ""));
            const tests = host.manifestOf(status.directory)?.tests ?? [];
            if (tests.length === 0)
                _fail("module " + label + " lists no test suites (\"tests\" in its module.json)");
            for (const test of tests)
                runnable.push({ module: status.id, url: ModuleFileRules.fileUrl(status.directory, test), file: test });
        }
        if (selected.length > 0) {
            runnable = runnable.filter(entry => selected.includes(suiteNameOf(entry.file)));
            // Only when every module loaded: a module that did not load is a failure of its
            // own, not a wrong name
            const unknown = selected.filter(name => !runnable.some(entry => suiteNameOf(entry.file) === name));
            if (unknown.length > 0 && host.statuses.every(status => status.state === "loaded")) {
                console.log("MODULE-SUITES-UNKNOWN: " + unknown.join(" "));
                runnable = [];
            }
        }
        console.log("MODULE-SUITES-EXPECTED: " + runnable.length);
        const suites = [];
        for (const entry of runnable) {
            const component = Qt.createComponent(entry.url, Component.PreferSynchronous);
            if (component.status !== Component.Ready) {
                _fail(entry.module + ": " + entry.file + " does not compile: " + component.errorString().trim());
                continue;
            }
            let suite = null;
            try {
                suite = component.createObject(root);
            } catch (error) {
                _fail(entry.module + ": " + entry.file + " threw while being created: " + error);
            }
            if (!suite) {
                _fail(entry.module + ": " + entry.file + " could not be created");
                continue;
            }
            suites.push(suite);
        }
        _suites = suites;
    }

    // The cap on a suite's own time limit (TestCase.timeLimitMs)
    readonly property int maxTimeLimitMs: 60000
    function timeLimitOf(suite) {
        const limit = typeof suite.timeLimitMs === "number" && suite.timeLimitMs > 0 ? suite.timeLimitMs : 20000;
        return Math.min(limit, maxTimeLimitMs);
    }

    property var _clock: Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            root._waited += interval;
            if (root._phase === "loading") {
                // The required programs are checked by a process: wait for it (15 s at most)
                if (!root._settled() && root._waited < 15000)
                    return;
                root._runSuites();
                root._phase = "running";
                root._waited = 0;
                return;
            }
            // Each asynchronous suite has its own limit (TestCase.timeLimitMs, 20 s by default,
            // at most maxTimeLimitMs), counted from the start of the suites (they run side by side);
            // the runner quits once none is pending
            const pending = root._suites.filter(suite => suite.asynchronous && !suite.done);
            for (const suite of pending) {
                if (root._waited >= root.timeLimitOf(suite)) {
                    suite.fail("timed out (" + Math.round(root.timeLimitOf(suite) / 1000) + " s)");
                    suite.finish();
                }
            }
            if (pending.some(suite => !suite.done))
                return;
            root.host.unload();
            Qt.quit();
        }
    }

    Component.onCompleted: {
        const value = Quickshell.env("H2S_TEST_MODULES");
        host.load(typeof value === "string" ? value : "", {});
        if (host.directories.length === 0) {
            _fail("no module directory given (H2S_TEST_MODULES; run tests/run-modules.sh <dir>…)");
            _phase = "running";
        }
    }
}
