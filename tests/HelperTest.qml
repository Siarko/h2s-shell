import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.helper

// The shell's side of its helper program: what HelperRules makes of `h2s-helper --version`
// (ready, out of date, failed in each way, text from outside capped on one line), and the
// reading itself (singletons/helper/HelperVersionRead.qml) run for real against stand-ins
// (tests/fixtures/helper: a helper of this protocol, of another, one that fails, one that
// says something else, one with markup in its version) and a path that is not there. The
// real helper is tests/run-helper.sh's. And the shell's Helper here, started without the
// launcher: no helper. Asynchronous: each reading is a process.
TestCase {
    id: suite
    suiteName: "Helper"
    asynchronous: true

    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/helper"

    function _rules() {
        const read = HelperRules.readVersion;
        const ok = stdout => ({ ok: true, code: 0, stdout: stdout, timedOut: false, failedToStart: false, truncated: false });
        const current = "{\"version\":\"2.0.0\",\"protocol\":" + HelperRules.protocol + "}";

        assertEqual(JSON.stringify(read(ok(current))), JSON.stringify({ state: "ready", version: "2.0.0", problem: "" }),
                    "this protocol: ready, with its version");
        assertEqual(read(ok("\n" + current + "\n\n")).state, "ready", "… blank lines around it do not matter");
        const old = read(ok("{\"version\":\"1.0.0\",\"protocol\":" + (HelperRules.protocol + 1) + "}"));
        assertEqual(old.state, "outdated", "another protocol: out of date");
        assertEqual(old.version, "1.0.0", "… its version kept");
        assert(old.problem.indexOf(String(HelperRules.protocol + 1)) >= 0, "… the problem names its protocol");

        assertEqual(read(null).state, "failed", "no result: failed");
        assertEqual(read({ failedToStart: true }).problem, "could not be started", "not started: failed, said so");
        assertEqual(read({ timedOut: true }).problem, "did not answer", "timed out: failed, said so");
        assertEqual(read({ ok: true, truncated: true, stdout: current }).state, "failed", "too much output: failed");
        assertEqual(read({ ok: false, code: 3, stdout: current }).problem, "failed (3)", "a non-zero status: failed, whatever it printed");
        for (const stdout of ["", "h2s-helper 2.0.0", "[1]", "null", "{\"version\":2,\"protocol\":1}",
                              "{\"version\":\"2\",\"protocol\":\"1\"}", "{\"version\":\"2\",\"protocol\":1.5}",
                              current + "\n" + current])
            assertEqual(read(ok(stdout)).state, "failed", "not the protocol's answer (" + JSON.stringify(stdout) + "): failed");
        const odd = read(ok("{\"version\":\"<b>" + "v".repeat(100) + "</b>\\nnext\",\"protocol\":" + HelperRules.protocol + "}"));
        assertEqual(odd.version.length, 40, "a version from outside is capped");
        assertEqual(odd.version.indexOf("\n"), -1, "… and on one line");

        assertEqual(HelperRules.logLine("", { state: "missing" }), "", "no helper: the launcher said so, nothing more");
        assertEqual(HelperRules.logLine("/x/h2s-helper", { state: "ready" }), "", "ready: nothing to say");
        assert(HelperRules.logLine("/x/h2s-helper", old).indexOf("out of date") >= 0, "out of date: said");
        assert(HelperRules.logLine("/x/h2s-helper", read(null)).indexOf("/x/h2s-helper") >= 0, "failed: said, with its path");
    }

    // ---- The readings, one after another --------------------------------------------------
    property var _cases: [
        { program: "ready", state: "ready", version: "2.0.0" },
        { program: "outdated", state: "outdated", version: "1.9.0" },
        { program: "fails", state: "failed", version: "" },
        { program: "garbage", state: "failed", version: "" },
        { program: "markup", state: "ready", version: ("<b>" + "v".repeat(100)).slice(0, 40) },
        { program: "not-there", state: "failed", version: "" }
    ]
    property var _reader: null
    property var _case: null
    property int _waited: 0

    property Component _readerComponent: Component {
        HelperVersionRead {}
    }

    function runAsync() {
        try {
            _rules();
        } catch (error) {
            fail("the rules threw: " + error);
        }
        assertEqual(Helper.path, "", "the shell started without the launcher has no helper");
        assertEqual(Helper.state, "missing", "… its state says so");
        assert(!Helper.available, "… and it is not available");
        _next();
    }

    function _next() {
        _reader?.destroy();
        _reader = null;
        _case = _cases.shift() ?? null;
        if (_case === null) {
            finish();
            return;
        }
        _waited = 0;
        _reader = _readerComponent.createObject(suite, { path: _fixtures + "/" + _case.program });
        _clock.start();
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        onTriggered: {
            const reader = suite._reader;
            suite._waited += interval;
            if (reader.state === "checking" && suite._waited < 10000)
                return;
            stop();
            const name = suite._case.program;
            suite.assertEqual(reader.state, suite._case.state, name + ": " + suite._case.state);
            suite.assertEqual(reader.version, suite._case.version, name + ": its version");
            if (suite._case.state === "failed")
                suite.assert(reader.problem !== "", name + ": the problem is said");
            suite._next();
        }
    }
}
