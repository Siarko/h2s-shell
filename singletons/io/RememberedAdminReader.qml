import QtQuick
import Quickshell
import qs.singletons

// The remembered administrator authorization's I/O; the shell's one instance is
// RememberedAdmin, which hands it the lock, the setting and the shell's process. Decisions
// are RememberRules'; this only runs the commands, every one a property so that a suite
// points it at stand-ins (tests/RememberedAdminReadingTest.qml):
//
// - scripts/pam-files.sh for the rule files, polkitd.conf in its three places and
//   /etc/NIXOS (it tells a file not there from one it cannot read), and `readlink -f` for
//   the program pkexec reports for the shell's timeout: what is installed (RememberRules.state);
// - gdbus for the logind session (`session/auto`: the caller's, else the user's display
//   session — the session polkit takes for a process outside one), asked until known; then
//   the authority's EnumerateTemporaryAuthorizations for that session: what is kept
//   (RememberRules.parseKept — structured, no command lines, absolute times);
// - gdbus for RevokeTemporaryAuthorizations of the session: the forgetting, session-wide.
//
// The list is read on readKept() (after a privileged run, after unlock — RememberedAdmin),
// after each revoke, and once a second only while `viewers` is above 0. A revoke comes at
// lock (unless the rule is absent and nothing is known to be kept; again when the lock came
// during another revoke), on forget(), at the time the setting gives (one timer, armed from
// the earliest obtained time) and at once when the list says "longer"; after one that
// failed or left the entry listed, that revoke waits on a doubling backoff. Nothing here asks for a password: polkit's authority answers these calls
// without one. A read started before a revoke, or overtaken by a newer read, is dropped
// (late answers lose); outcomes are logged when they change.
QtObject {
    id: root

    // ---- Inputs ----
    property bool locked: false
    property int minutes: 5
    property int pid: 0
    property string user: ""
    // The shell's trusted timeout (CommandTools.timeout)
    property string timeout: ""
    // Countdown views showing now: the list is read once a second while above 0
    property int viewers: 0

    // ---- Commands (seams) ----
    property var gdbusCommand: ["gdbus"]
    property var filesCommand: [Quickshell.shellDir + "/scripts/pam-files.sh"]
    property var resolveCommand: ["readlink", "-f", "--"]
    // Prepended to every file path read (a suite's scratch tree); the answers keep the real paths
    property string fileRoot: ""
    property var environment: ({})
    property int timeoutMs: 5000
    // After a revoke that failed, or after which the list still shows what it should have
    // ended, the time revoke is tried again only after this, doubling up to retryMaxMs
    property int retryBaseMs: 2000
    property int retryMaxMs: 60000
    // The wall clock in ms (a suite's seam: the revoke time without real minutes)
    property var now: () => Date.now()

    readonly property string nixosRulePath: "/etc/polkit-1/rules.d/10-nixos.rules"
    readonly property string nixosMarkPath: "/etc/NIXOS"

    // ---- Outputs ----
    // RememberRules.state's answer, or null before the first reading
    property var installed: null
    // "arch" | "nixos" | "" before the first reading
    property string system: ""
    // The program pkexec reports for the timeout (its path resolved), "" when not known
    property string program: ""
    // RememberRules.parseKept's answer, or null before the first list
    property var kept: null
    // Until when something stays kept (RememberRules.keptUntilMs), 0 for nothing
    readonly property real keptUntilMs: kept === null ? 0 : RememberRules.keptUntilMs(kept.entries, minutes)
    // What a privileged mark is told (RememberRules.remembered: frozen { kept, untilMs }): a
    // new object only when it changes — after a list, a change of the setting, and when what
    // is kept runs out (one timer, armed for that moment)
    readonly property var remembered: _remembered
    property var _remembered: RememberRules.remembered(null, minutes, 0)
    // The armed revoke time, 0 for none
    readonly property real revokeAtMs: _revokeTimer.running ? _revokeAt : 0
    // The last revoke's outcome: "" (none yet) | "forgotten" | "failed"; why it ran
    // ("lock", "forget", "time", "longer") and when it ended
    property string forgetOutcome: ""
    property string forgetReason: ""
    property real forgetAtMs: 0
    // Counters a suite waits on
    property int lists: 0
    property int readings: 0
    property int revokes: 0

    // ---- Requests ----
    function refresh() {
        const generation = ++_filesGeneration;
        const paths = [RememberRules.rulePath, nixosRulePath, nixosMarkPath].concat(RememberRules.confPaths);
        const answers = { files: null, program: undefined };
        const settle = () => {
            if (generation !== _filesGeneration || answers.files === null || answers.program === undefined)
                return;
            const files = answers.files;
            const text = path => files[path]?.text ?? (files[path]?.absent ? undefined : null);
            const nixos = files[nixosMarkPath]?.text !== undefined;
            const confs = {};
            for (const path of RememberRules.confPaths)
                confs[path] = text(path);
            system = nixos ? "nixos" : "arch";
            program = answers.program;
            installed = RememberRules.state({ rule: text(nixos ? nixosRulePath : RememberRules.rulePath), confs },
                                            { system, user, timeout, program: answers.program });
            readings += 1;
        };
        _run(filesCommand.concat(paths.map(path => fileRoot + path)), (lines, result) => {
            const answer = PamStackRules.filesAnswer(lines, result, paths.map(path => fileRoot + path)).answers;
            const files = {};
            for (const path of paths)
                files[path] = answer[fileRoot + path];
            answers.files = files;
            settle();
        });
        if (timeout === "") {
            answers.program = "";
            settle();
        } else {
            _run(resolveCommand.concat([timeout]), (lines, result) => {
                const program = result.ok && lines.length === 1 ? lines[0] : "";
                answers.program = program.startsWith("/") ? program : "";
                settle();
            });
        }
    }

    function readKept() {
        // A revoke under way reads the list when it ends
        if (_revoking)
            return;
        const generation = ++_listGeneration;
        if (_sessionId === "") {
            _run(gdbusCommand.concat(["call", "--system", "--dest", "org.freedesktop.login1",
                                      "--object-path", "/org/freedesktop/login1/session/auto",
                                      "--method", "org.freedesktop.DBus.Properties.Get",
                                      "org.freedesktop.login1.Session", "Id"]), (lines, result) => {
                if (generation !== _listGeneration)
                    return;
                _sessionId = result.ok ? RememberRules.sessionIdOf(lines.join("\n")) : "";
                if (_sessionId === "") {
                    _listed(RememberRules.parseKept(null, now(), pid, _systemSeconds()), "no logind session");
                    return;
                }
                _enumerate(generation);
            });
            return;
        }
        _enumerate(generation);
    }

    // "Forget now"
    function forget() {
        _revoke("forget");
    }

    // ---- Inside ----
    property int _filesGeneration: 0
    property int _listGeneration: 0
    property string _sessionId: ""
    property bool _revoking: false
    property real _revokeAt: 0
    property string _listProblem: ""
    property string _forgetLogged: ""
    // Revokes that failed (or did nothing) in a row; a revoke reported done whose list is
    // not read yet; the lock's revoke waiting for one under way
    property int _failures: 0
    property bool _checkAfterRevoke: false
    property bool _lockPending: false

    function _systemSeconds() {
        return installed?.seconds ?? -1;
    }

    function _run(argv, done) {
        const lines = [];
        _runner.start(argv, {
            timeoutMs: timeoutMs,
            killAfterMs: 1000,
            environment: environment,
            maxOutputBytes: 1048576,
            keepOutput: false,
            onLine: (line, stream) => {
                if (stream === "stdout" && line.trim() !== "")
                    lines.push(line);
            },
            done: result => done(lines, result)
        });
    }

    function _enumerate(generation) {
        const subject = RememberRules.sessionSubject(_sessionId);
        _run(gdbusCommand.concat(["call", "--system", "--dest", "org.freedesktop.PolicyKit1",
                                  "--object-path", "/org/freedesktop/PolicyKit1/Authority",
                                  "--method", "org.freedesktop.PolicyKit1.Authority.EnumerateTemporaryAuthorizations",
                                  subject]), (lines, result) => {
            if (generation !== _listGeneration)
                return;
            const list = RememberRules.parseKept(result.ok ? lines.join("\n") : null, now(), pid, _systemSeconds());
            _listed(list, result.ok ? list.reason : "the list could not be read");
        });
    }

    function _listed(list, problem) {
        kept = list;
        lists += 1;
        const said = problem === "" || problem === "longer" ? "" : problem;
        if (said !== _listProblem) {
            if (said !== "")
                console.warn("[RememberedAdmin] what is remembered is not known: " + said);
            else if (_listProblem !== "")
                console.log("[RememberedAdmin] what is remembered is known again");
            _listProblem = said;
        }
        const step = RememberRules.revokeStep(list, minutes, now());
        // Reported done, yet still due: it did nothing
        const ineffective = _checkAfterRevoke && step.now;
        _checkAfterRevoke = false;
        if (ineffective) {
            forgetOutcome = "failed";
            _logForget(false, forgetReason);
            _armRetry();
        }
        if (!step.now) {
            _failures = 0;
            _retryTimer.stop();
        }
        if (step.now) {
            _revokeTimer.stop();
            // Waiting on the backoff after a revoke that failed or did nothing
            if (!_retryTimer.running)
                _revoke(list.reason === "longer" ? "longer" : "time");
        } else if (step.atMs > 0) {
            _revokeAt = step.atMs;
            _revokeTimer.interval = Math.max(1, Math.min(step.atMs - now(), 2147483647));
            _revokeTimer.restart();
        } else {
            _revokeTimer.stop();
        }
    }

    function _logForget(ok, reason) {
        const outcome = ok ? "forgotten" : "failed";
        if (outcome === _forgetLogged)
            return;
        if (ok)
            console.log("[RememberedAdmin] the remembered password was forgotten (" + reason + ")");
        else
            console.warn("[RememberedAdmin] could not forget the remembered password (" + reason + ")");
        _forgetLogged = outcome;
    }

    function _armRetry() {
        _failures += 1;
        _retryTimer.interval = Math.min(retryBaseMs * Math.pow(2, Math.min(_failures - 1, 20)), retryMaxMs);
        _retryTimer.restart();
    }

    function _revoke(reason) {
        if (_revoking) {
            // The lock's revoke runs again when this one ends: what was obtained just before
            // the lock, or a revoke that fails, must not leave a password kept while locked
            if (reason === "lock")
                _lockPending = true;
            return;
        }
        // A read under way is dropped: it may list what this revoke ends
        _listGeneration++;
        _revokeTimer.stop();
        _revoking = true;
        const finish = ok => {
            _revoking = false;
            forgetOutcome = ok ? "forgotten" : "failed";
            forgetReason = reason;
            forgetAtMs = now();
            revokes += 1;
            _logForget(ok, reason);
            if (ok)
                _checkAfterRevoke = true;
            else
                _armRetry();
            if (_lockPending) {
                _lockPending = false;
                if (locked) {
                    _revoke("lock");
                    return;
                }
            }
            readKept();
        };
        const doRevoke = () => {
            const subject = RememberRules.sessionSubject(_sessionId);
            _run(gdbusCommand.concat(["call", "--system", "--dest", "org.freedesktop.PolicyKit1",
                                      "--object-path", "/org/freedesktop/PolicyKit1/Authority",
                                      "--method", "org.freedesktop.PolicyKit1.Authority.RevokeTemporaryAuthorizations",
                                      subject]), (lines, result) => finish(result.ok));
        };
        if (_sessionId !== "") {
            doRevoke();
            return;
        }
        _run(gdbusCommand.concat(["call", "--system", "--dest", "org.freedesktop.login1",
                                  "--object-path", "/org/freedesktop/login1/session/auto",
                                  "--method", "org.freedesktop.DBus.Properties.Get",
                                  "org.freedesktop.login1.Session", "Id"]), (lines, result) => {
            _sessionId = result.ok ? RememberRules.sessionIdOf(lines.join("\n")) : "";
            if (_sessionId === "")
                finish(false);
            else
                doRevoke();
        });
    }

    // Not revoked at lock only when it is known that nothing is kept and the rule is absent
    onLockedChanged: {
        if (locked && !(installed?.rule === "none" && kept?.known === true && kept.entries.length === 0))
            _revoke("lock");
        else if (!locked)
            readKept();
    }

    property Timer _retryTimer: Timer {
        onTriggered: root.readKept()
    }

    property Timer _revokeTimer: Timer {
        onTriggered: {
            // Early (Qt's timers may) or late (a suspend): the list decides again
            if (root.now() < root._revokeAt)
                root.readKept();
            else
                root._revoke("time");
        }
    }

    // The countdown's reading, only while a view shows it
    function _updateRemembered() {
        const next = RememberRules.remembered(kept, minutes, now());
        if (next.kept !== _remembered.kept || next.untilMs !== _remembered.untilMs)
            _remembered = next;
        if (next.kept) {
            _expiry.interval = Math.max(1, Math.min(next.untilMs - now(), 2147483647));
            _expiry.restart();
        } else {
            _expiry.stop();
        }
    }
    onKeptChanged: _updateRemembered()
    onMinutesChanged: _updateRemembered()

    // Fires when what is kept runs out (early, as after a clock change: armed again)
    property Timer _expiry: Timer {
        onTriggered: root._updateRemembered()
    }

    property Timer _countdown: Timer {
        interval: 1000
        repeat: true
        running: root.viewers > 0
        onTriggered: root.readKept()
    }

    property CommandRunner _runner: CommandRunner {}
}
