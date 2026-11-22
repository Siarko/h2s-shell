import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.lock

// What Idle reads from logind about sleep, and the sleep call (singletons/lock/LogindSleep.qml),
// run for real against a stand-in for gdbus (tests/fixtures/logind-sleep, linked into a
// scratch directory whose files say what it answers): CanSuspend yes, na and challenge,
// logind's IdleAction, a gdbus that fails, is not there or never ends (unknown, never "yes");
// the Suspend call made once, non-interactive (`false`), taken and refused. Never the real
// gdbus or system bus: the reader is given the scratch directory as its tool directory, and
// the stand-in only notes the call. Asynchronous.
TestCase {
    id: suite
    suiteName: "LogindSleepReading"
    asynchronous: true

    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/logind-sleep"
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-logind-sleep-test-" + Date.now()

    property var _reader: null
    property bool _ready: false
    property int _readsBefore: 0
    property real _hangStarted: 0
    // The last suspended() answer: { ok, error }, null before
    property var _suspended: null
    property string _calls: ""

    property Component _readerComponent: Component {
        LogindSleep {}
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

    // The next read, after `script` (run with the scratch directory as $1) set the answers
    function _readAfter(script) {
        _ready = false;
        _sh(script, [_scratch], () => {
            suite._readsBefore = suite._reader.reads;
            suite._reader.refresh();
            suite._ready = true;
        });
    }

    function _answered() {
        return _ready && _reader.reads > _readsBefore && !_reader.running;
    }

    function _support() {
        return JSON.stringify(_reader.support);
    }

    // The Suspend call, after `script`; its calls file read once it answered
    function _suspendAfter(script) {
        _ready = false;
        _suspended = null;
        _calls = "";
        _sh(script, [_scratch], () => {
            suite.assert(suite._reader.suspend(), "the call starts");
            suite.assert(!suite._reader.suspend(), "… a second while it runs does not");
            suite._ready = true;
        });
    }

    function _callsRead() {
        _calls = "";
        _sh("cat \"$1/calls\" 2> /dev/null; true", [_scratch], null, text => suite._calls = text || "none");
    }

    function runAsync() {
        _then("the stand-in is in place", () => _ready, () => {
            _reader = _readerComponent.createObject(suite, { toolDirectory: _scratch, watchdog: 500 });
            _reader.suspended.connect((ok, error) => suite._suspended = { ok: ok, error: error });
            assertEqual(_support(), JSON.stringify({ canSuspend: "unknown", idleAction: null }), "before a read: unknown");
            _readAfter("echo yes > \"$1/can-suspend\"; echo 'ignore 1800000000' > \"$1/idle-action\"");
        });
        _then("the first read answered", () => _answered(), () => {
            assertEqual(_support(), JSON.stringify({ canSuspend: "yes", idleAction: { action: "ignore", after: 1800 } }),
                        "CanSuspend yes; IdleAction ignore after 30 min");
            _readAfter("echo na > \"$1/can-suspend\"; echo 'suspend 900000000' > \"$1/idle-action\"");
        });
        _then("the na read answered", () => _answered(), () => {
            assertEqual(_support(), JSON.stringify({ canSuspend: "na", idleAction: { action: "suspend", after: 900 } }),
                        "CanSuspend na; logind suspending by itself after 15 min");
            _readAfter("echo challenge > \"$1/can-suspend\"; rm -f \"$1/idle-action\"");
        });
        _then("the challenge read answered", () => _answered(), () => {
            assertEqual(_support(), JSON.stringify({ canSuspend: "challenge", idleAction: null }),
                        "CanSuspend challenge; IdleAction not read: null");
            _readAfter("echo yes > \"$1/can-suspend\"");
        });
        _then("yes before gdbus goes missing", () => _answered(), () => {
            assertEqual(_reader.support.canSuspend, "yes", "yes again");
            _reader.toolDirectory = _scratch + "/missing";
            _readAfter("true");
        });
        _then("the read without a gdbus answered", () => _answered(), () => {
            assertEqual(_support(), JSON.stringify({ canSuspend: "unknown", idleAction: null }), "no gdbus: from yes to unknown, never yes");
            _reader.toolDirectory = _scratch;
            _readAfter("rm -f \"$1/can-suspend\"");
        });
        _then("the read against a failing gdbus answered", () => _answered(), () => {
            assertEqual(_reader.support.canSuspend, "unknown", "gdbus fails (no logind): unknown");
            _readAfter("echo yes > \"$1/can-suspend\"");
        });
        _then("yes before a hanging gdbus", () => _answered(), () => {
            assertEqual(_reader.support.canSuspend, "yes", "yes again");
            _ready = false;
            _sh("touch \"$1/hang\"", [_scratch], () => {
                suite._readsBefore = suite._reader.reads;
                suite._hangStarted = Date.now();
                suite._reader.refresh();
                suite._ready = true;
            });
        });
        _then("the hanging read answered", () => _answered(), () => {
            assertEqual(_reader.support.canSuspend, "unknown", "a gdbus that never ends: unknown");
            const took = Date.now() - _hangStarted;
            assert(took >= 400 && took < 3000, "… ended by the watchdog (500 ms here), took " + took + " ms");
            _suspendAfter("rm -f \"$1/hang\"");
        });
        _then("the sleep call answered", () => _ready && _suspended !== null, () => {
            assertEqual(JSON.stringify(_suspended), JSON.stringify({ ok: true, error: "" }), "Suspend: taken");
            _callsRead();
        });
        _then("the calls read", () => _calls !== "", () => {
            assertEqual(_calls.trim(), "Suspend false", "… asked once, non-interactive (false: never a password prompt)");
            _suspendAfter("touch \"$1/refuse\"; rm -f \"$1/calls\"");
        });
        _then("the refused call answered", () => _ready && _suspended !== null, () => {
            assertEqual(_suspended.ok, false, "Suspend refused: not taken");
            assert(_suspended.error.includes("OperationInProgress"), "… with logind's words: " + _suspended.error);
            _callsRead();
        });
        _then("the calls read again", () => _calls !== "", () => {
            assertEqual(_calls.trim(), "Suspend false", "… asked once");
        });
        _clock.start();
        _sh("set -e; mkdir -p \"$1\"; ln -s \"$2/gdbus\" \"$1/\"", [_scratch, _fixtures], code => {
            suite.assertEqual(code, 0, "the stand-in is linked into a scratch directory");
            suite._ready = true;
        });
    }

    function _sh(script, args, done, read) {
        const process = _shell.createObject(suite, { command: ["sh", "-c", script, "sh"].concat(args), done: done, read: read ?? null });
        process.running = true;
    }

    property Component _shell: Component {
        Process {
            id: _process
            property var done: null
            property var read: null
            property bool _exited: false
            property bool _finished: false
            function _over() {
                if (_exited && _finished)
                    _process.destroy();
            }
            stdout: StdioCollector {
                onStreamFinished: {
                    _process.read?.(text);
                    _process._finished = true;
                    _process._over();
                }
            }
            onExited: code => {
                _process.done?.(code);
                _process._exited = true;
                _process._over();
            }
        }
    }
}
