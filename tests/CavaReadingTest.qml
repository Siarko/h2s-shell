import QtQuick
import Quickshell
import qs.singletons.media

// CavaReader run for real against stand-ins for cava (tests/fixtures/cava): one that cannot
// run (the dynamic loader's message, exit 127) is "failed" with that reason, tried again
// with a backoff, and logged once however often it fails; switched to one that works, the
// levels come, the state is "running" and that is logged once; stopped, nothing waits.
// Never the real cava. Asynchronous: each step is a process.
TestCase {
    id: suite
    suiteName: "CavaReading"
    asynchronous: true

    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/cava"

    property var _reader: null
    property var _logged: []
    property var _levels: []

    property Component _readerComponent: Component {
        CavaReader {
            retryMs: 20
            retryMostMs: 80
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
        _reader?.destroy();
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
        _then("the working cava's levels came", () => _levels.length >= 2, () => {
            assertEqual(_reader.state, "running", "levels: running");
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
        });
        _clock.start();
    }
}
