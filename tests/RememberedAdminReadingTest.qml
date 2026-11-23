import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.singletons.io

// The reading and forgetting behind RememberedAdmin (singletons/io/RememberedAdminReader.qml),
// run for real against stand-ins: scripts/pam-files.sh on a scratch tree in the system's
// place (the rule file, polkitd.conf, /etc/NIXOS), the real `readlink -f` on a scratch
// timeout, and a stand-in gdbus that answers logind's session id, polkit's list from a file
// and its revoke (noting every call). Covers: what is installed (Arch, NixOS, a conf that
// cannot be read), no session, the list, the revoke at the chosen time through the clock
// seam, at once when polkit keeps longer than its conf says, at lock (and not while the rule
// is known absent), on forget(), a revoke that fails, a list read overtaken by a revoke,
// the countdown's reading while a view shows it, and what a privileged mark is told (kept
// until its end, turned back when it runs out). Never the real bus, polkit or /etc.
// Asynchronous.
TestCase {
    id: suite
    suiteName: "RememberedAdminReading"
    asynchronous: true
    timeLimitMs: 60000

    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-remembered-admin-test-" + Date.now()
    readonly property string _tree: _scratch + "/tree"
    readonly property string _bus: _scratch + "/bus"
    readonly property string _timeout: _scratch + "/bin/timeout"
    readonly property int _pid: 4242
    readonly property string _exec: "org.freedesktop.policykit.exec"

    property var _reader: null
    property bool _ready: false
    // The reader's clock is the wall clock moved by this much (the revoke time without real minutes)
    property real _offsetMs: 0
    property int _mark: 0
    property string _log: ""

    property Component _readerComponent: Component {
        RememberedAdminReader {}
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
            if (!ready && waited < 15000)
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
        _sh("chmod -R u+rwx \"$1\" 2> /dev/null; rm -rf \"$1\"", [_scratch], () => suite.finish());
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

    // The stand-in gdbus's calls so far, one line each, handed to `then` (marked ready first)
    function _withCalls(then) {
        _ready = false;
        const process = _catter.createObject(suite, { command: ["cat", _bus + "/log"] });
        process.then = text => {
            suite._ready = true;
            then(text.split("\n").filter(line => line !== ""));
        };
        process.running = true;
    }

    property Component _catter: Component {
        Process {
            id: _cat
            property var then: null
            stdout: StdioCollector {
                onStreamFinished: {
                    _cat.then?.(text);
                    _cat.destroy();
                }
            }
        }
    }

    // Writes files (path relative to the scratch directory → text), then marks ready
    function _write(files, done) {
        _ready = false;
        const names = Object.keys(files);
        const script = names.map((name, i) => "mkdir -p \"$(dirname \"$1/" + name + "\")\" && printf '%s' \"$" + (i + 2) + "\" > \"$1/" + name + "\"").join(" && ");
        _sh(script, [_scratch].concat(names.map(name => files[name])), code => {
            suite.assertEqual(code, 0, "written: " + names.join(", "));
            done?.();
            suite._ready = true;
        });
    }

    function _nowSeconds() {
        return Math.floor((Date.now() + _offsetMs) / 1000);
    }

    // polkit's answer as gdbus prints it, for [{ id, pid, obtained, expires }] (seconds)
    function _list(entries) {
        if (entries.length === 0)
            return "(@a(ss(sa{sv})tt) [],)\n";
        return "([" + entries.map(entry => "('" + entry.id + "', '" + _exec + "', ('unix-process', {'pid': <uint32 " + entry.pid
                                    + ">, 'start-time': <uint64 5>, 'uid': <1000>}), uint64 " + entry.obtained + ", uint64 " + entry.expires + ")").join(", ")
            + "],)\n";
    }

    function _setUp() {
        const standIn = "#!/usr/bin/env sh\n"
            + "# Stand-in for gdbus (tests/RememberedAdminReadingTest.qml): no bus is reached\n"
            + "d='" + _bus + "'\n"
            + "printf '%s\\n' \"$*\" >> \"$d/log\"\n"
            + "case \"$*\" in\n"
            + "  *Properties.Get*) cat \"$d/session\"; exit \"$(cat \"$d/session-code\")\" ;;\n"
            + "  *EnumerateTemporaryAuthorizations*) list=$(cat \"$d/list\")\n"
            + "    if [ -e \"$d/hold\" ] && mv \"$d/hold\" \"$d/held\" 2> /dev/null; then\n"
            + "      while [ -e \"$d/held\" ]; do sleep 0.02; done; printf '%s\\n' \"$list\"; : > \"$d/released\"; exit 0\n"
            + "    fi\n"
            + "    printf '%s\\n' \"$list\"; exit \"$(cat \"$d/list-code\")\" ;;\n"
            + "  *RevokeTemporaryAuthorizations*) code=$(cat \"$d/revoke-code\")\n"
            + "    if [ -e \"$d/hold-revoke\" ] && mv \"$d/hold-revoke\" \"$d/held-revoke\" 2> /dev/null; then\n"
            + "      while [ -e \"$d/held-revoke\" ]; do sleep 0.02; done\n"
            + "    fi\n"
            + "    [ \"$code\" = 0 ] && [ ! -e \"$d/keep-list\" ] && printf '(@a(ss(sa{sv})tt) [],)\\n' > \"$d/list\"\n"
            + "    printf '()\\n'; exit \"$code\" ;;\n"
            + "esac\n"
            + "exit 1\n";
        _sh([
            "set -e",
            "mkdir -p \"$1/bus\" \"$1/bin\" \"$1/tree\"",
            "printf '%s' \"$2\" > \"$1/bus/gdbus\"; chmod +x \"$1/bus/gdbus\"",
            ": > \"$1/bus/log\"",
            "printf \"(<'7'>,)\\n\" > \"$1/bus/session\"; printf 1 > \"$1/bus/session-code\"",
            "printf '(@a(ss(sa{sv})tt) [],)\\n' > \"$1/bus/list\"; printf 0 > \"$1/bus/list-code\"; printf 0 > \"$1/bus/revoke-code\"",
            "printf '#!/bin/sh\\n' > \"$1/bin/timeout\"; chmod +x \"$1/bin/timeout\""
        ].join("\n"), [_scratch, standIn], code => {
            suite.assertEqual(code, 0, "the stand-ins are made");
            suite._ready = true;
        });
    }

    function runAsync() {
        _setUp();
        let readings = 0, lists = 0, revokes = 0;
        const read = () => {
            readings = _reader.readings;
            _reader.refresh();
        };
        const listed = () => _reader.lists > lists;
        const readList = () => {
            lists = _reader.lists;
            _reader.readKept();
        };
        _then("the stand-ins are in place", () => _ready, () => {
            _reader = _readerComponent.createObject(suite, {
                gdbusCommand: [_bus + "/gdbus"],
                fileRoot: _tree,
                pid: _pid,
                user: "alex",
                timeout: _timeout,
                minutes: 5,
                retryBaseMs: 600000,
                now: () => Date.now() + suite._offsetMs
            });
            assertEqual(_reader.installed, null, "before a reading: nothing known");
            assertEqual(_reader.kept, null, "… nothing listed");
            read();
            readList();
        });
        _then("the first reading and list", () => _reader.readings > readings && listed(), () => {
            assertEqual(JSON.stringify([_reader.installed.rule, _reader.installed.conf, _reader.installed.seconds, _reader.installed.secondsReason]),
                        JSON.stringify(["none", "none", 300, "default"]), "nothing installed, no conf: polkit's default");
            assertEqual(_reader.system, "arch", "no /etc/NIXOS: Arch");
            assert(_reader.program.startsWith("/") && _reader.program.endsWith("/bin/timeout"), "the timeout resolved by readlink: " + _reader.program);
            assertEqual(_reader.kept.known + " " + _reader.kept.reason, "false unread", "no logind session: unknown, never nothing kept");
            _withCalls(calls => {
                assertEqual(calls.filter(line => line.includes("EnumerateTemporaryAuthorizations")).length, 0, "… polkit not asked without a session");
                // Locked with the rule absent but what is kept unknown: forgotten all the same
                revokes = _reader.revokes;
                _reader.locked = true;
            });
        });
        _then("locked, what is kept unknown", () => _ready && _reader.revokes > revokes, () => {
            assertEqual(_reader.forgetOutcome + " " + _reader.forgetReason, "failed lock",
                        "the rule absent, what is kept unknown: the lock forgets (here without a session: could not)");
            _reader.locked = false;
            _write({ "bus/session-code": "0" });
        });
        _then("a session", () => _ready, () => readList());
        _then("nothing kept, known", () => listed(), () => {
            assertEqual(_reader.kept.known + " " + _reader.kept.entries.length, "true 0", "nothing kept, known");
            assertEqual(_reader._retryTimer.running, false, "nothing due: no retry waits");
            revokes = _reader.revokes;
            lists = _reader.lists;
            _reader.locked = true;
            _reader.locked = false;
        });
        _then("unlocked: the list read again", () => listed(), () => {
            assertEqual(_reader.revokes, revokes, "locked with the rule absent and nothing kept: nothing forgotten");
            _write({
                     ["tree" + RememberRules.rulePath]: RememberRules.ruleText({ user: "alex", timeout: _timeout, program: _reader.program }),
                     ["tree" + RememberRules.confPath]: RememberRules.confText(600) });
        });
        _then("the rule written", () => _ready, () => {
            read();
            readList();
        });
        _then("read with the rule and a session", () => _reader.readings > readings && listed(), () => {
            assertEqual(JSON.stringify([_reader.installed.rule, _reader.installed.conf, _reader.installed.seconds, _reader.installed.secondsSource]),
                        JSON.stringify(["ours", "ours", 600, RememberRules.confPath]), "the rule and our conf installed, 10 min");
            assertEqual(_reader.kept.known + " " + _reader.kept.entries.length, "true 0", "nothing kept: known");
            assertEqual(_reader.revokeAtMs, 0, "nothing kept: no revoke armed");
            _withCalls(calls => {
            assert(calls.some(line => line.includes("--object-path /org/freedesktop/login1/session/auto") && line.endsWith("org.freedesktop.login1.Session Id")),
                   "the session asked of logind's session/auto");
            assert(calls.some(line => line.includes("EnumerateTemporaryAuthorizations ('unix-session', {'session-id': <'7'>})")),
                   "polkit's list asked for that session");
            _mark = calls.length;
            readList();
            });
        });
        _then("read again", () => _ready && listed(), () => _withCalls(calls => {
            assertEqual(calls.slice(_mark).filter(line => line.includes("Properties.Get")).length, 0, "the session asked once only");
            const now = _nowSeconds();
            _write({ "bus/list": _list([{ id: "other", pid: 777, obtained: now - 10, expires: now + 590 },
                                        { id: "ours", pid: _pid, obtained: now - 60, expires: now + 540 }]) });
        }));
        _then("something kept", () => _ready, () => readList());
        _then("the list with our entry", () => listed(), () => {
            const entries = _reader.kept.entries;
            assertEqual(entries.map(entry => entry.id).join(","), "ours", "only the shell's process's entry");
            assertEqual(_reader.revokeAtMs, entries[0].obtainedMs + 300000, "5 of 10 min: the revoke armed for obtained plus 5 min");
            assertEqual(_reader.keptUntilMs, _reader.revokeAtMs, "… kept until then");
            // The clock moved to just before the revoke time: the timer fires in a moment
            _withCalls(calls => {
                _mark = calls.length;
                revokes = _reader.revokes;
                _offsetMs += _reader.revokeAtMs - (Date.now() + _offsetMs) - 100;
                readList();
            });
        });
        _then("revoked at the chosen time", () => _ready && _reader.revokes > revokes && !_reader.kept?.entries?.length && _reader.lists > lists, () => {
            assertEqual(_reader.forgetOutcome + " " + _reader.forgetReason, "forgotten time", "forgotten at the chosen time");
            assertEqual(_reader.revokeAtMs, 0, "… nothing armed after");
            _withCalls(calls => {
                assert(calls.slice(_mark).some(line => line.includes("RevokeTemporaryAuthorizations ('unix-session', {'session-id': <'7'>})")),
                       "… polkit's revoke for the session");
                _offsetMs = 0;
                const now = _nowSeconds();
                revokes = _reader.revokes;
                _write({ "bus/list": _list([{ id: "hour", pid: _pid, obtained: now - 60, expires: now + 3540 }]) });
            });
        });
        _then("kept an hour while the conf says 10 min", () => _ready, () => readList());
        _then("revoked at once: longer", () => _reader.revokes > revokes, () => {
            assertEqual(_reader.forgetOutcome + " " + _reader.forgetReason, "forgotten longer", "polkit keeps longer than its conf: forgotten at once");
            revokes = _reader.revokes;
            _reader.locked = true;
        });
        _then("revoked at lock", () => _reader.revokes > revokes, () => {
            assertEqual(_reader.forgetReason, "lock", "the lock forgets");
            lists = _reader.lists;
            _reader.locked = false;
        });
        _then("unlocked: read", () => listed(), () => {
            revokes = _reader.revokes;
            _reader.forget();
        });
        _then("Forget now", () => _reader.revokes > revokes, () => {
            assertEqual(_reader.forgetOutcome + " " + _reader.forgetReason, "forgotten forget", "forget(): forgotten");
            _write({ "bus/revoke-code": "1" });
        });
        _then("the revoke made to fail", () => _ready, () => {
            revokes = _reader.revokes;
            _reader.forget();
        });
        _then("a revoke that fails", () => _reader.revokes > revokes && listed(), () => {
            assertEqual(_reader.forgetOutcome + " " + _reader.forgetReason, "failed forget", "polkit refused: could not forget");
            assertEqual(_reader._retryTimer.running, false, "nothing was due: no retry");
            const now = _nowSeconds();
            // Due a minute ago (obtained 2 min ago, the setting 1 min), within polkit's 10 min
            _reader.minutes = 1;
            _write({ "bus/list": _list([{ id: "due", pid: _pid, obtained: now - 120, expires: now + 180 }]) });
        });
        _then("a due entry, the revoke failing", () => _ready, () => _withCalls(calls => {
            _mark = calls.length;
            revokes = _reader.revokes;
            readList();
        }));
        _then("the due revoke failed", () => _ready && _reader.revokes > revokes && listed(), () => {
            assertEqual(_reader.forgetOutcome, "failed", "the time revoke failed");
            assertEqual(_reader._retryTimer.running, true, "… a retry waits on the backoff");
            readList();
        });
        _then("read again while the retry waits", () => listed(), () => readList());
        _then("and again", () => listed(), () => _withCalls(calls => {
            assertEqual(calls.slice(_mark).filter(line => line.includes("RevokeTemporaryAuthorizations")).length, 1,
                        "a failed revoke is not tried again at each reading: once until the backoff ends");
            assertEqual(_reader.forgetOutcome, "failed", "… still failed");
            // polkit answers again, yet leaves the entry: the revoke did nothing
            _write({ "bus/revoke-code": "0", "bus/keep-list": "" }, () => suite._mark = calls.length);
        }));
        _then("the retry, the entry left", () => _ready, () => {
            revokes = _reader.revokes;
            lists = _reader.lists;
            // The backoff's end, without waiting it out
            _reader._retryTimer.stop();
            _reader._retryTimer.triggered();
        });
        _then("revoked, still listed", () => _reader.revokes > revokes && _reader.lists > lists && !_reader._revoking, () => {
            assertEqual(_reader.forgetOutcome, "failed", "polkit said done, the list still shows it: could not forget");
            assertEqual(_reader._retryTimer.running, true, "… a retry waits");
            readList();
        });
        _then("read while the retry waits", () => listed(), () => _withCalls(calls => {
            assertEqual(calls.slice(_mark).filter(line => line.includes("RevokeTemporaryAuthorizations")).length, 1,
                        "a revoke that did nothing is not repeated at once");
            _sh("rm -f \"$1/bus/keep-list\"", [_scratch], () => {
                revokes = _reader.revokes;
                lists = _reader.lists;
                _reader._retryTimer.stop();
                _reader._retryTimer.triggered();
            });
        }));
        _then("the retry works", () => _reader.revokes > revokes && _reader.lists > lists && !_reader._revoking && _reader.kept.entries.length === 0, () => {
            assertEqual(_reader.forgetOutcome + " " + _reader.forgetReason, "forgotten time", "the retry forgot it");
            assertEqual(_reader._retryTimer.running, false, "… nothing waits after");
            _reader.minutes = 5;
            // The lock during another revoke: its own revoke runs when that one ends
            _write({ "bus/hold-revoke": "" });
        });
        _then("a revoke to be held", () => _ready, () => {
            revokes = _reader.revokes;
            _reader.forget();
        });
        _then("the forget held", () => _reader._revoking, () => _sh("while [ ! -e \"$1/bus/held-revoke\" ]; do sleep 0.02; done", [_scratch], () => {
            suite._withCalls(calls => {
                suite._mark = calls.length;
                suite._reader.locked = true;
                suite._sh("rm -f \"$1/bus/held-revoke\"", [suite._scratch], () => {});
            });
        }));
        _then("both revokes done", () => _ready && _reader.revokes >= revokes + 2 && !_reader._revoking, () => {
            assertEqual(_reader.forgetReason, "lock", "the lock's revoke ran after the one under way");
            _withCalls(calls => {
                assertEqual(calls.slice(_mark).filter(line => line.includes("RevokeTemporaryAuthorizations")).length, 1, "… once more");
                lists = _reader.lists;
                _reader.locked = false;
            });
        });
        let staleShown = false;
        const watchStale = () => {
            if (_reader.kept?.entries?.some(entry => entry.id === "stale"))
                staleShown = true;
        };
        _then("unlocked", () => _ready && listed(), () => {
            const now = _nowSeconds();
            _write({ "bus/hold": "", "bus/hold-revoke": "",
                     "bus/list": _list([{ id: "stale", pid: _pid, obtained: now - 5, expires: now + 595 }]) });
        });
        _then("a list read and a revoke to be held", () => _ready, () => {
            _reader.keptChanged.connect(watchStale);
            lists = _reader.lists;
            revokes = _reader.revokes;
            _reader.readKept();
        });
        // The read under way when a revoke starts answers while the revoke is still held:
        // its list may show what the revoke ends, so it must not be published
        _then("the read held", () => _reader._runner.running > 0, () => _sh("while [ ! -e \"$1/bus/held\" ]; do sleep 0.02; done", [_scratch], () => {
            suite._reader.forget();
            suite._sh("while [ ! -e \"$1/bus/held-revoke\" ]; do sleep 0.02; done; rm -f \"$1/bus/held\"; "
                      + "while [ ! -e \"$1/bus/released\" ]; do sleep 0.02; done", [suite._scratch], () => suite._ready = true);
            suite._ready = false;
        }));
        _then("the read answered, the revoke still held", () => _ready && _reader._runner.running === 1, () => {
            assertEqual(staleShown, false, "the read from before the revoke is dropped: its stale entry never shown");
            assertEqual(_reader._revoking, true, "… while the revoke is still under way");
            _sh("rm -f \"$1/bus/held-revoke\"", [_scratch], () => {});
        });
        _then("the revoke done and listed again", () => _reader.revokes > revokes && _reader.lists > lists && !_reader._revoking, () => {
            _reader.keptChanged.disconnect(watchStale);
            assertEqual(staleShown, false, "the stale entry never shown");
            assertEqual(_reader.kept.entries.length, 0, "after the revoke: nothing kept");
            _write({ ["tree" + RememberRules.confPath]: RememberRules.confText(600) });
        });
        _then("a moment", () => _ready, () => _sh("chmod 000 \"$1\"", [_tree + RememberRules.confPath], () => read()));
        _then("the conf unreadable", () => _reader.readings > readings, () => {
            assertEqual(_reader.installed.seconds + " " + _reader.installed.secondsReason, "-1 unreadable", "a conf that cannot be read: the length unknown");
            const block = RememberRules.ruleText({ user: "alex", timeout: _timeout, program: _reader.program });
            _write({ "tree/etc/NIXOS": "", ["tree" + _reader.nixosRulePath]: "/* NixOS */\npolkit.addRule(function(action, subject) {\n});\n\n" + block });
        });
        _then("NixOS files written", () => _ready, () => read());
        _then("NixOS read", () => _reader.readings > readings, () => {
            assertEqual(_reader.system + " " + _reader.installed.rule + " " + _reader.installed.conf, "nixos ours system",
                        "/etc/NIXOS: the rule read from the system's rules file");
            lists = _reader.lists;
            _reader.viewers = 1;
        });
        _then("a countdown shown: read without being asked", () => _reader.lists > lists, () => {
            _reader.viewers = 0;
            assertEqual(_reader._countdown.running, false, "no view: the countdown's reading stops");
            assertEqual(JSON.stringify(_reader.remembered), JSON.stringify({ kept: false, untilMs: 0 }), "nothing kept: a mark is told so");
            const now = _nowSeconds();
            _write({ "bus/list": _list([{ id: "runs-out", pid: _pid, obtained: now - 60, expires: now + 240 }]) });
        });
        let told = null;
        _then("an entry that runs out by itself", () => _ready, () => readList());
        _then("what a mark is told", () => listed() && _reader.remembered.kept, () => {
            const until = _reader.kept.entries[0].untilMs;
            assertEqual(JSON.stringify(_reader.remembered), JSON.stringify({ kept: true, untilMs: until }), "kept: until polkit's expiry");
            assert(Object.isFrozen(_reader.remembered), "… frozen");
            assertEqual(_reader.revokeAtMs, 0, "… with no revoke armed: it runs out by itself");
            const left = until - (Date.now() + _offsetMs);
            assert(_reader._expiry.running && Math.abs(_reader._expiry.interval - left) < 5000, "… a timer armed for its end: " + _reader._expiry.interval + " ms, " + left + " left");
            told = _reader.remembered;
            readList();
        });
        _then("the same list again", () => listed(), () => {
            assert(_reader.remembered === told, "the same list read again: the same object, no change told");
            // The clock past its end; the timer's firing, without waiting it out
            _offsetMs += told.untilMs - (Date.now() + _offsetMs) + 1;
            _reader._expiry.stop();
            _reader._expiry.triggered();
            assertEqual(JSON.stringify(_reader.remembered), JSON.stringify({ kept: false, untilMs: 0 }), "run out: not kept any more, without a reading");
            assertEqual(_reader._expiry.running, false, "… and nothing armed");
            _offsetMs = 0;
        });
        _clock.start();
    }
}
