import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.lock

// The reading behind SleepLockNotice (singletons/lock/SleepLockers.qml), run for real
// against a stand-in for gdbus (tests/fixtures/sleep-lockers, linked into a scratch
// directory whose `inhibitors` it prints as logind's ListInhibitors): a locker found, the
// shell's own inhibitor and other users' left out, a possible locker, none, and a gdbus
// that fails or is not there — unknown, never "none". Never the real gdbus or system bus:
// the reader is given the scratch directory as its tool directory. Asynchronous.
TestCase {
    id: suite
    suiteName: "SleepLockersReading"
    asynchronous: true

    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/sleep-lockers"
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-sleep-lockers-test-" + Date.now()

    property var _reader: null
    property bool _ready: false
    property int _readsBefore: 0

    property Component _readerComponent: Component {
        SleepLockers {}
    }

    // ---- A tiny scheduler: each step waits for its condition (or its deadline), then runs ----
    property var _steps: []

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
        _sh("rm -rf \"$1\"", [_scratch], () => suite.finish());
    }

    // The next read, with `inhibitors` copied from the fixture named (none: removed)
    function _readWith(fixture) {
        _ready = false;
        const script = fixture === "" ? "rm -f \"$1/inhibitors\"" : "cp \"$2/inhibitors-$3\" \"$1/inhibitors\"";
        _sh(script, [_scratch, _fixtures, fixture], () => {
            suite._readsBefore = suite._reader.reads;
            suite._reader.start();
            suite._ready = true;
        });
    }

    function _answered() {
        return _ready && _reader.reads > _readsBefore && !_reader.running;
    }

    function _lockers() {
        return JSON.stringify(_reader.lockers);
    }

    function runAsync() {
        _then("the stand-in is in place", () => _ready, () => {
            _reader = _readerComponent.createObject(suite, { toolDirectory: _scratch });
            assertEqual(_reader.lockers.state, "unknown", "before a read: unknown");
            _readWith("gnome");
        });
        _then("the first read answered", () => _answered(), () => {
            assertEqual(_lockers(), JSON.stringify({ state: "present", names: ["GNOME Shell"] }),
                        "a locker of this user's found; the shell's own inhibitor and root's services left out");
            _readWith("hypridle");
        });
        _then("the second read answered", () => _answered(), () => {
            assertEqual(_lockers(), JSON.stringify({ state: "possible", names: ["hypridle"] }), "hypridle alone: possibly a locker");
            _readWith("none");
        });
        _then("the third read answered", () => _answered(), () => {
            assertEqual(_lockers(), JSON.stringify({ state: "none", names: [] }), "no inhibitor: none");
            _readWith("");
        });
        _then("the read against a failing gdbus answered", () => _answered(), () => {
            assertEqual(_lockers(), JSON.stringify({ state: "unknown", names: [] }), "gdbus fails (no logind): unknown, never none");
            _reader.destroy();
            _reader = _readerComponent.createObject(suite, { toolDirectory: _scratch + "/missing" });
            _readWith("none");
        });
        _then("the read without a gdbus answered", () => _answered(), () => {
            assertEqual(_lockers(), JSON.stringify({ state: "unknown", names: [] }), "no gdbus at all: unknown");
        });
        _clock.start();
        _sh("set -e; mkdir -p \"$1\"; ln -s \"$2/gdbus\" \"$1/\"", [_scratch, _fixtures], code => {
            suite.assertEqual(code, 0, "the stand-in is linked into a scratch directory");
            suite._ready = true;
        });
    }

    function _sh(script, args, done) {
        const process = _shell.createObject(suite, { command: ["sh", "-c", script, "sh"].concat(args), done: done });
        process.running = true;
    }

    property Component _shell: Component {
        Process {
            id: _process
            property var done: null
            onExited: code => {
                _process.done?.(code);
                _process.destroy();
            }
        }
    }
}
