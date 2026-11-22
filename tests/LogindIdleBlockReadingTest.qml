import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.lock

// The reading of logind's idle block behind Idle (singletons/lock/LogindIdleBlock.qml), run
// for real against a stand-in for gdbus (tests/fixtures/logind-idle, linked into a scratch
// directory whose `inhibitors` it prints as logind's ListInhibitors): an idle block of this
// user's held (other users' and sleep delays left out), none, and a gdbus that fails, is not
// there, answers something malformed or never ends (its watchdog) — unknown, never "free",
// each after a free read on the same reader. Never the real gdbus or system bus: the reader
// is given the scratch directory as its tool directory. Asynchronous.
TestCase {
    id: suite
    suiteName: "LogindIdleBlockReading"
    asynchronous: true

    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/logind-idle"
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-logind-idle-test-" + Date.now()

    property var _reader: null
    property bool _ready: false
    property int _readsBefore: 0
    property real _hangStarted: 0

    property Component _readerComponent: Component {
        LogindIdleBlock {}
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

    function _block() {
        return JSON.stringify(_reader.block);
    }

    function runAsync() {
        const unknown = JSON.stringify({ held: "unknown", holders: [] });
        const free = JSON.stringify({ held: false, holders: [] });
        _then("the stand-in is in place", () => _ready, () => {
            _reader = _readerComponent.createObject(suite, { toolDirectory: _scratch, watchdog: 500 });
            assertEqual(_reader.block.held, "unknown", "before a read: unknown");
            _readWith("mpv");
        });
        _then("the first read answered", () => _answered(), () => {
            assertEqual(_block(), JSON.stringify({ held: true, holders: [{ who: "mpv", why: "Playing 'film.mkv'" }] }),
                        "an idle block of this user's: held; the greeter's, sleep delays and the shell's own left out");
            assertEqual(JSON.stringify(_reader.sleepBlock), JSON.stringify({ held: true, holders: [{ who: "mpv", why: "Playing 'film.mkv'" }] }),
                        "the same read's sleep block: mpv's sleep:idle block holds sleep; delays do not");
            _readWith("none");
        });
        _then("the second read answered", () => _answered(), () => {
            assertEqual(_block(), free, "no idle block of this user's: free");
            assertEqual(_reader.sleepBlock.held, false, "… no sleep block either");
            _readWith("malformed");
        });
        _then("the malformed read answered", () => _answered(), () => {
            assertEqual(_block(), unknown, "a malformed answer: unknown, never free");
            _readWith("none");
        });
        _then("free before the failing gdbus", () => _answered(), () => {
            assertEqual(_block(), free, "free again");
            _readWith("");
        });
        _then("the read against a failing gdbus answered", () => _answered(), () => {
            assertEqual(_block(), unknown, "gdbus fails (no logind): from free to unknown, never free");
            _readWith("none");
        });
        _then("free before gdbus goes missing", () => _answered(), () => {
            assertEqual(_block(), free, "free again");
            _reader.toolDirectory = _scratch + "/missing";
            _readWith("none");
        });
        _then("the read without a gdbus answered", () => _answered(), () => {
            assertEqual(_block(), unknown, "no gdbus at all: from free to unknown");
            _reader.toolDirectory = _scratch;
            _readWith("none");
        });
        _then("free before a hanging gdbus", () => _answered(), () => {
            assertEqual(_block(), free, "free again");
            _ready = false;
            _sh("touch \"$1/hang\"", [_scratch], () => {
                suite._readsBefore = suite._reader.reads;
                suite._hangStarted = Date.now();
                suite._reader.start();
                suite._ready = true;
            });
        });
        _then("the hanging read answered", () => _answered(), () => {
            assertEqual(_block(), unknown, "a gdbus that never ends: unknown, its partial list discarded");
            assertEqual(_reader.sleepBlock.held, "unknown", "… its sleep block too");
            const took = Date.now() - _hangStarted;
            assert(took >= 400 && took < 3000, "… ended by the watchdog (500 ms here), took " + took + " ms");
            assert(!_reader.running, "… the process ended");
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
