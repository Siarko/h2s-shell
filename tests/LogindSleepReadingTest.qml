import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.lock

// What Idle reads from logind about sleep, and the sleep call (singletons/lock/LogindSleep.qml),
// run for real against a stand-in for gdbus (tests/fixtures/logind-sleep, linked into a
// scratch directory whose files say what it answers): CanSuspend yes, na and challenge,
// logind's IdleAction, a gdbus that fails, is not there or never ends (unknown, never "yes");
// CanHibernate and CanSuspendThenHibernate, the swap table, memory, lockdown, resume device,
// NixOS and sleep.conf with a drop-in (a stand-in systemd-analyze, files under a scratch
// root); the Suspend call made once, non-interactive (`false`), taken, refused, and one that
// never answers (ended by its watchdog); Hibernate and SuspendThenHibernate the same way, and
// no other method. Never the real gdbus, system bus or system files: the reader is given the
// scratch directory as its tool directory and file root, and the stand-in only notes the
// call. Asynchronous.
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
    property string _method: ""
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
        _sh(script, [_scratch, _fixtures], () => {
            suite._readsBefore = suite._reader.reads;
            suite._reader.refresh();
            suite._ready = true;
        });
    }

    function _answered() {
        return _ready && _reader.reads > _readsBefore && !_reader.running;
    }

    // The sleep half of the support (the hibernation half: _hibernation)
    function _support() {
        return JSON.stringify({ canSuspend: _reader.support.canSuspend, idleAction: _reader.support.idleAction });
    }

    function _hibernation() {
        const support = _reader.support;
        return JSON.stringify({ canHibernate: support.canHibernate, canSuspendThenHibernate: support.canSuspendThenHibernate,
                                hibernation: support.hibernation });
    }

    // The Suspend call, after `script`; its calls file read once it answered
    function _suspendAfter(script, method) {
        _ready = false;
        _suspended = null;
        _calls = "";
        _sh(script, [_scratch], () => {
            suite.assert(suite._reader.suspend(method), "the call starts" + (method ? " (" + method + ")" : ""));
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
            _reader = _readerComponent.createObject(suite, { toolDirectory: _scratch, fileRoot: _scratch + "/root", watchdog: 500,
                                                             suspendWatchdog: 500 });
            _reader.suspended.connect((ok, error, method) => { suite._suspended = { ok: ok, error: error }; suite._method = method; });
            assertEqual(_support(), JSON.stringify({ canSuspend: "unknown", idleAction: null }), "before a read: unknown");
            // Whether this is NixOS not known yet (Distribution not answered): the read waits
            _reader.nixos = undefined;
            _readAfter("echo yes > \"$1/can-suspend\"; echo 'ignore 1800000000' > \"$1/idle-action\"");
        });
        _then("the read asked for", () => _ready, () => {
            assert(!_reader.running && _reader.reads === _readsBefore, "the distribution not known: no read started");
        });
        _then("the wait for the distribution timed out", () => _reader.reads > _readsBefore, () => {
            assert(!_reader.running && _reader.support.canSuspend === "unknown" && _reader.support.hibernation.nixos === null,
                   "no distribution within the watchdog: answered, everything unknown");
            // … and made once it answers (the next step waits for it): not NixOS
            _readsBefore = _reader.reads;
            _reader.nixos = false;
        });
        _then("the first read answered", () => _answered(), () => {
            assertEqual(_support(), JSON.stringify({ canSuspend: "yes", idleAction: { action: "ignore", after: 1800 } }),
                        "CanSuspend yes; IdleAction ignore after 30 min");
            assertEqual(_hibernation(), JSON.stringify({ canHibernate: "unknown", canSuspendThenHibernate: "unknown", hibernation: {
                swaps: null, memoryInUse: -1, lockdown: "unknown", resume: "unknown", delay: { state: "unknown" }, nixos: false } }),
                "nothing about hibernation answered or there: unknown, never yes; the distribution not NixOS: not NixOS");
            _readAfter("set -e; r=\"$1/root\"; mkdir -p \"$r/proc\" \"$r/sys/kernel/security\" \"$r/sys/power\" \"$r/etc\"; "
                + "echo na > \"$1/can-hibernate\"; echo yes > \"$1/can-suspend-then-hibernate\"; "
                + "printf 'Filename\\t\\tType\\tSize\\tUsed\\tPriority\\n/dev/zram0 partition\\t4194300\\t0\\t100\\n' > \"$r/proc/swaps\"; "
                + "printf 'MemTotal: 32000000 kB\\nMemAvailable: 30000000 kB\\n' > \"$r/proc/meminfo\"; "
                + "echo '[none] integrity confidentiality' > \"$r/sys/kernel/security/lockdown\"; echo 0:0 > \"$r/sys/power/resume\"; "
                + "echo 'root=UUID=x rw quiet' > \"$r/proc/cmdline\"; "
                + "printf '# /etc/systemd/sleep.conf\\n[Sleep]\\n#HibernateDelaySec=\\n\\n# /etc/systemd/sleep.conf.d/h2s-shell.conf\\n[Sleep]\\nHibernateDelaySec=10800\\n' > \"$1/sleep-conf\"; "
                + "ln -sf \"$2/systemd-analyze\" \"$1/\"");
        });
        _then("the hibernation read answered", () => _answered(), () => {
            assertEqual(_hibernation(), JSON.stringify({ canHibernate: "na", canSuspendThenHibernate: "yes", hibernation: {
                swaps: [{ name: "/dev/zram0", type: "partition", kib: 4194300, zram: true }], memoryInUse: 2000000, lockdown: "none",
                resume: false, delay: { state: "set", seconds: 10800, file: "/etc/systemd/sleep.conf.d/h2s-shell.conf" }, nixos: false } }),
                "CanHibernate na, CanSuspendThenHibernate yes; zram only, lockdown none, no resume device; the drop-in's delay 3 h");
            assertEqual(HibernateRules.unavailable(Object.assign({ answer: _reader.support.canHibernate }, _reader.support.hibernation)),
                        "Not available here: no swap space to save the session to (only zram, which is lost at power-off).",
                        "… said as the page says it");
            _reader.nixos = true;
            _readAfter("set -e; r=\"$1/root\"; echo 'none [integrity] confidentiality' > \"$r/sys/kernel/security/lockdown\"; "
                + "rm \"$1/sleep-conf\" \"$1/can-hibernate\"");
        });
        _then("the second hibernation read answered", () => _answered(), () => {
            const read = _reader.support;
            assertEqual(read.canHibernate + " " + read.hibernation.lockdown + " " + read.hibernation.nixos + " " + JSON.stringify(read.hibernation.delay),
                        "unknown integrity true {\"state\":\"unknown\"}",
                        "CanHibernate failing: unknown; lockdown integrity; NixOS; sleep.conf not printed: the delay unknown");
            _reader.nixos = null;
            _readAfter("echo na > \"$1/can-suspend\"; echo 'suspend 900000000' > \"$1/idle-action\"");
        });
        _then("the na read answered", () => _answered(), () => {
            assertEqual(_support(), JSON.stringify({ canSuspend: "na", idleAction: { action: "suspend", after: 900 } }),
                        "CanSuspend na; logind suspending by itself after 15 min");
            assertEqual(_reader.support.hibernation.nixos, null, "… the distribution cannot be told: whether NixOS not known");
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
            _hangStarted = Date.now();
            _suspendAfter("rm -f \"$1/refuse\"; touch \"$1/hang\"");
        });
        _then("the hanging call answered", () => _ready && _suspended !== null, () => {
            assertEqual(_suspended.ok, false, "a Suspend call that never ends: not taken");
            assert(/did not answer/.test(_suspended.error), "… said so: " + _suspended.error);
            const took = Date.now() - _hangStarted;
            assert(took >= 400 && took < 3000, "… ended by its watchdog (500 ms here), took " + took + " ms");
            assert(!_reader.suspending, "… no longer running: a later sleep can be asked");
            assert(!_reader.suspend("PowerOff"), "no call but the three sleeps");
            _suspendAfter("rm -f \"$1/hang\" \"$1/calls\"", "Hibernate");
        });
        _then("the hibernate call answered", () => _ready && _suspended !== null, () => {
            assertEqual(JSON.stringify(_suspended), JSON.stringify({ ok: true, error: "" }), "Hibernate: taken");
            assertEqual(_method, "Hibernate", "… the answer names the method asked");
            _callsRead();
        });
        _then("the hibernate call read", () => _calls !== "", () => {
            assertEqual(_calls.trim(), "Hibernate false", "… asked once, non-interactive");
            _suspendAfter("rm -f \"$1/calls\"", "SuspendThenHibernate");
        });
        _then("the suspend-then-hibernate call answered", () => _ready && _suspended !== null, () => {
            assertEqual(_suspended.ok, true, "SuspendThenHibernate: taken");
            assertEqual(_method, "SuspendThenHibernate", "… the answer names the method asked");
            _callsRead();
        });
        _then("the suspend-then-hibernate call read", () => _calls !== "", () => {
            assertEqual(_calls.trim(), "SuspendThenHibernate false", "… asked once, non-interactive");
            assertEqual(_readerComponent.createObject(suite).watchdog >= 25000, true,
                        "the reads' watchdog by default outlasts five calls of 5 s each");
            _readsBefore = _reader.reads;
            _reader.refresh();
            _reader.refresh();
        });
        _then("a read asked while one ran followed it", () => _reader.reads >= _readsBefore + 2 && !_reader.running, () => {
            assertEqual(_reader.reads, _readsBefore + 2, "asked during a read: read once more after it, not dropped");
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
