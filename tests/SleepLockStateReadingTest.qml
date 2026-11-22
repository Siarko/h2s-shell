import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.lock

// The reading behind SleepLockNotice (singletons/lock/SleepLockState.qml), run for real
// against stand-ins for hyprctl and gdbus (tests/fixtures/sleep-lock-state, linked into a
// scratch directory whose `compositor` and `hint` they answer): the compositor's word first,
// logind's LockedHint without it, false hints and failures unknown — never unlocked by
// default. Never the real hyprctl, gdbus or system bus: the reader is given the scratch
// directory. Asynchronous.
TestCase {
    id: suite
    suiteName: "SleepLockStateReading"
    asynchronous: true

    readonly property string _fixtures: Quickshell.shellDir + "/tests/fixtures/sleep-lock-state"
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-sleep-lock-state-test-" + Date.now()
    readonly property string _session: "/org/freedesktop/login1/session/_7"

    property var _reader: null
    property bool _ready: false
    property int _readsBefore: 0
    property string _calls: ""
    property double _startedAt: 0
    property Timer _stopSoon: Timer {
        interval: 200
        onTriggered: suite._reader.stop()
    }

    property Component _readerComponent: Component {
        SleepLockState {}
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

    // The next read, the compositor and the hint as given ("" for none: that stand-in fails)
    function _readWith(compositor, hint, started) {
        _ready = false;
        _sh("rm -f \"$1/compositor\" \"$1/hint\" \"$1/calls\"\n"
            + "[ -z \"$2\" ] || echo \"$2\" > \"$1/compositor\"\n"
            + "[ -z \"$3\" ] || echo \"$3\" > \"$1/hint\"", [_scratch, compositor, hint], () => {
            suite._readsBefore = suite._reader.reads;
            suite._startedAt = Date.now();
            suite._reader.start();
            started?.();
            suite._ready = true;
        });
    }

    function _answered() {
        return _ready && _reader.reads > _readsBefore && !_reader.running;
    }

    // The gdbus stand-in's calls, read into _calls before `then` runs (no step goes on meanwhile)
    function _readCalls(then) {
        _ready = false;
        _sh("cat \"$1/calls\" 2> /dev/null; true", [_scratch], null, output => {
            suite._calls = output;
            then();
        });
    }

    function _make(properties) {
        _reader?.destroy();
        _reader = _readerComponent.createObject(suite, Object.assign({
            toolDirectory: _scratch, hyprctl: _scratch + "/hyprctl", sessionPath: _session, onHyprland: true
        }, properties ?? {}));
    }

    function runAsync() {
        _then("the stand-ins are in place", () => _ready, () => {
            _make();
            assertEqual(_reader.outcome, "unknown", "before a read: unknown");
            _readWith("true", "false");
        });
        _then("compositor locked: answered", () => _answered(), () => {
            assertEqual(_reader.outcome, "locked", "the compositor says locked (its answer over several lines): locked");
            _readWith("false", "true");
        });
        _then("compositor unlocked: answered", () => _answered(), () => {
            assertEqual(_reader.outcome, "unlocked", "the compositor says unlocked: unlocked, whatever the hint");
            _make({ onHyprland: false });
            _readWith("false", "true");
        });
        _then("off Hyprland, hint true: answered", () => _answered(), () => {
            assertEqual(_reader.outcome, "locked", "off Hyprland the compositor is not asked; LockedHint true: locked");
            _readCalls(() => {
                assertEqual(suite._calls.trim(), "LockedHint " + suite._session, "… asked for the shell's session");
                suite._readWith("", "false");
            });
        });
        _then("off Hyprland, hint false: answered", () => _answered(), () => {
            assertEqual(_reader.outcome, "unknown", "LockedHint false proves nothing: unknown");
            _make();
            _readWith("", "");
        });
        _then("both failing: answered", () => _answered(), () => {
            assertEqual(_reader.outcome, "unknown", "hyprctl and gdbus both fail: unknown, never unlocked");
            _make({ onHyprland: false, sessionPath: "" });
            _readWith("", "true");
        });
        _then("no session known: answered", () => _answered(), () => {
            assertEqual(_reader.outcome, "unknown", "no session path: logind not asked, unknown");
            _readCalls(() => {
                assertEqual(suite._calls.trim(), "", "… no call made");
                suite._make({ onHyprland: false, toolDirectory: suite._scratch + "/missing" });
                suite._readWith("", "true");
            });
        });
        _then("no gdbus at all: answered", () => _answered(), () => {
            assertEqual(_reader.outcome, "unknown", "no gdbus at all: unknown");
            _make();
            _readWith("hang", "true");
        });
        _then("a hyprctl that never answers: answered", () => _answered(), () => {
            const took = Date.now() - suite._startedAt;
            assert(took < 3000, "a hyprctl that never answers is given a second, not more (" + took + " ms)");
            assertEqual(_reader.outcome, "locked", "… and the hint read after it");
            _readWith("hang", "", () => suite._stopSoon.start());
        });
        _then("a read stopped: answered", () => _answered(), () => {
            assert(Date.now() - suite._startedAt < 1000, "stop() ends a running read at once");
            assertEqual(_reader.outcome, "unknown", "… as unknown");
        });
        _clock.start();
        _sh("set -e; mkdir -p \"$1\"; ln -s \"$2/gdbus\" \"$2/hyprctl\" \"$1/\"", [_scratch, _fixtures], code => {
            suite.assertEqual(code, 0, "the stand-ins are linked into a scratch directory");
            suite._ready = true;
        });
    }

    function _sh(script, args, done, output) {
        const process = _shell.createObject(suite, { command: ["sh", "-c", script, "sh"].concat(args), done: done, output: output ?? null });
        process.running = true;
    }

    property Component _shell: Component {
        Process {
            id: _process
            property var done: null
            property var output: null
            // With `output` it is answered (and goes) when its output has ended, else at its exit
            stdout: StdioCollector {
                onStreamFinished: {
                    if (_process.output === null)
                        return;
                    _process.output(text);
                    _process.destroy();
                }
            }
            onExited: code => {
                if (_process.output !== null)
                    return;
                _process.done?.(code);
                _process.destroy();
            }
        }
    }
}
