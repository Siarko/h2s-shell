import QtQuick
import Quickshell
import qs.singletons.media

// CavaReader run for real against stand-ins for cava (tests/fixtures/cava): one that cannot
// run (the dynamic loader's message, exit 127) is "failed" with that reason, tried again
// with a backoff, and logged once however often it fails; switched to one that works, the
// levels come, the state is "running" once it has run a while, and that is logged once;
// stopped, nothing waits. A program that is not there is not tried again until asked. One
// that prints a frame and dies is not counted as running. A run left behind by a restart
// says nothing that counts. Restarts asked in one turn start one run. Never the real cava.
// Asynchronous: each step is a process.
TestCase {
    id: suite
    suiteName: "CavaReading"
    asynchronous: true

    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/cava"

    property var _reader: null
    property var _logged: []
    property var _levels: []
    // The other readers, each with what it logged and the levels it gave
    property var _missing: null
    property var _missingLogged: []
    property var _flaky: null
    property var _flakyLogged: []
    property var _stale: null
    property var _staleLogged: []
    property var _staleLevels: []
    property var _once: null

    property Component _readerComponent: Component {
        CavaReader {
            retryMs: 20
            retryMostMs: 80
            healthyMs: 100
        }
    }

    // ---- Each step waits for its condition (or its deadline), then runs ----
    property var _steps: []

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
    }

    property Timer _clock: Timer {
        interval: 20
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite._end();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {}
            if (!ready && waited < 10000)
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

    function _end() {
        for (const reader of [_reader, _missing, _flaky, _stale, _once])
            reader?.destroy();
        suite.finish();
    }

    function runAsync() {
        _reader = _readerComponent.createObject(suite, { program: _fixtures + "/cava-broken", configPath: "/dev/null" });
        _reader.logged.connect(line => suite._logged = suite._logged.concat([line]));
        _reader.levels.connect(line => suite._levels = suite._levels.concat([line]));
        assertEqual(_reader.state, "stopped", "not active: stopped");
        _reader.active = true;

        _then("the broken cava failed three times", () => _reader.failures >= 3, () => {
            assertEqual(_reader.state, "failed", "a cava that cannot run: failed");
            assertEqual(_reader.problem, "cava exited with code 127: cava: error while loading shared libraries: libsndio.so.7: cannot open shared object file: No such file or directory",
                "… with its exit code and what it said");
            assertEqual(_logged.length, 1, "… logged once, not at each try");
            assert(_logged[0]?.includes("code 127") ?? false, "… the line names the problem");
            assertEqual(_levels.length, 0, "… no levels");
            _reader.program = _fixtures + "/cava";
        });
        // Running once it has given levels for healthyMs: waited on, not inferred from a count of lines
        _then("the working cava runs", () => _reader.state === "running" && _levels.length >= 2, () => {
            assertEqual(_reader.problem, "", "… no problem");
            assertEqual(_reader.failures, 0, "… the failures start over");
            assertEqual(_levels[0], "10;20;30;40;40;30;20;10;", "… each line as cava printed it");
            assertEqual(JSON.stringify(_logged.slice(1)), JSON.stringify(["cava runs again"]), "… logged once that it runs again");
            _reader.active = false;
        });
        _then("stopped", () => _reader.state === "stopped", () => {
            assert(!_reader._retry.running, "stopped: no retry waits");
            assert(_reader._current === null, "… no run is left");
            assertEqual(_reader.failures, 0, "… no failures counted");

            _missing = _readerComponent.createObject(suite, { program: _fixtures + "/no-such-cava", configPath: "/dev/null" });
            _missing.logged.connect(line => suite._missingLogged = suite._missingLogged.concat([line]));
            _missing.active = true;
        });
        _then("the missing cava failed", () => _missing.state === "failed", () => {
            assertEqual(_missing.problem, "cava could not be started", "a cava that is not there: could not be started");
            assert(!_missing._retry.running, "… not tried again by itself");
            assertEqual(_missing.runs, 1, "… one run");
            _missing.requestRestart();
        });
        _then("the missing cava, asked again, failed again", () => _missing.runs === 2 && _missing.state === "failed" && _missing.failures === 2, () => {
            assertEqual(_missingLogged.length, 1, "… the same outcome, logged once");
            assert(!_missing._retry.running, "… and again not tried by itself");

            // A healthy window far past its short life: never counted as running, however loaded
            _flaky = _readerComponent.createObject(suite, { program: _fixtures + "/cava-flaky", configPath: "/dev/null", healthyMs: 60000 });
            _flaky.logged.connect(line => suite._flakyLogged = suite._flakyLogged.concat([line]));
            _flaky.active = true;
        });
        _then("the flaky cava failed four times", () => _flaky.failures >= 4, () => {
            assertEqual(_flaky.state, "failed", "a frame and then dead: failed, not running");
            assertEqual(_flakyLogged.length, 1, "… logged once, no \"runs again\" between its deaths");
            _flaky.active = false;

            _stale = _readerComponent.createObject(suite, { program: _fixtures + "/cava-stubborn", configPath: "/dev/null" });
            _stale.logged.connect(line => suite._staleLogged = suite._staleLogged.concat([line]));
            _stale.levels.connect(line => suite._staleLevels = suite._staleLevels.concat([line]));
            _stale.active = true;
        });
        _then("the stubborn cava is ready", () => _staleLevels.includes("ready"), () => {
            _stale.program = _fixtures + "/cava";
            _stale.requestRestart();
        });
        _then("the run after the restart is running", () => _stale.state === "running" && _stale._oldRunsEnded >= 1, () => {
            assert(!_staleLevels.includes("stale"), "a run left behind: its last line dropped");
            assertEqual(_stale.failures, 0, "… its end counts no failure");
            assertEqual(JSON.stringify(_staleLogged), "[]", "… and logs nothing");

            _once = _readerComponent.createObject(suite, { program: _fixtures + "/cava", configPath: "/dev/null" });
            _once.active = true;
            _once.requestRestart();
            _once.requestRestart();
        });
        _then("the reader asked three times in one turn runs", () => _once.state === "running", () => {
            assertEqual(_once.runs, 1, "restarts asked in one turn: one run");
        });
        _clock.start();
    }
}
