import QtQuick
import qs.singletons
import qs.singletons.io as Io

// A command run as root through pkexec, the shell's way (module API 1.0; 1.2: an absolute
// path, checked first) — polkit asks for the password through the shell's own prompt or
// whichever agent runs:
//
//   PrivilegedAction { id: admin }
//   admin.run([tailscalePath, "up"], "Connecting Tailscale", result => { … })
//
// run(command, what, done, environment) queues `pkexec <command…>` (one at a time per object,
// and in the shell's one queue of runs as administrator: singletons/PrivilegedRuns.qml, one
// password question at a time) and calls done({ ok, code, dismissed, refused, notFound,
// lines, error }):
//   ok         it ran and exited 0
//   notFound   (1.2) command[0] is not an absolute path to an executable regular file —
//              checked BEFORE pkexec is asked, so a missing program never shows as "not
//              authorised": a plain failure, notified as "<what> failed" with the reason
//              (unless notifyFailures is false); pkexec is not run, nothing is denied
//   dismissed  pkexec exited 126: the prompt was dismissed or the password not accepted —
//              nothing is shown (the user chose it); put the state back. (1.11) Also a run
//              still waiting when the session locks, or asked for while it is locked:
//              then with `blocked: "locked"`, and pkexec was not run
//   refused    pkexec exited 127: not authorised, or no authentication agent answered — the
//              shell says so once, with the way out (Authentication.reportDenied(what))
//   otherwise  the command itself failed: notified as "<what> failed" with its error, unless
//              notifyFailures is false (a VPN provider emits failed() instead)
// No time limit: the command decides how long it takes. The object destroyed (its module
// turned off): its runs leave the queue, a started one is cancelled, nothing is called.
// Replaced by `module.privileged.start` (1.11): a time limit, `what` in the prompt, live output.
// (1.36) Runs only from a module's code (the call's stack names the module), with its
// manifest's `privileged` block, approved, and command[0] the path of a declared, trusted
// program (module.programs) — else answered { blocked: "undeclared", error } before any
// prompt, the reason in the module's status.
// What cannot be told apart: a command that itself exits 126 or 127 looks exactly like pkexec's
// own 126 / 127 (pkexec passes the command's status through). Give a command that may exit
// with those its own wrapper, or read its output, before taking `dismissed` / `refused` as
// the user's answer. (pkexec also exits 127 when it cannot run the program — the check above
// is there so that this does not happen for a program that is simply missing.)
// `environment` ({ NAME: value }) goes to pkexec's environment — but pkexec clears the
// environment of what it runs: pass what the command needs as arguments, never a secret.
// In module test mode (API 1.10) `elevate` must be a module's stand-in, `<testPrograms>/pkexec`
// (its handle's `programs.pkexec.path` when it names pkexec): anything else — the default
// "pkexec" included — is answered { ok: false, code: -1, error } and nothing runs
// (ModuleRules.testElevateProblem), so a module's suites never meet the real pkexec.
// A module written for an API below 1.10 (the run made from its code alone) may still name a
// stand-in that lies anywhere, by its absolute path, until slice Z removes that: it runs
// unless a check finds it is the real pkexec or a setuid file, and a check that fails
// counts as real (ModuleRules, "The test-mode gate").
QtObject {
    id: root

    // What runs the command as root. "pkexec" by its name (the default) is the shell's
    // trusted, setuid pkexec (PrivilegedRuns.pkexec), never one found first on PATH; none
    // found: the run fails, not available. (1.36) Anything else outside module test mode, or
    // more than one word, is refused. A module's suites put its stand-in here.
    property var elevate: ["pkexec"]
    // "<what> failed" notifications for a command that ran and failed
    property bool notifyFailures: true
    readonly property bool busy: _current !== null || _queue.length > 0 || _probe.busy

    function run(givenCommand, what, done, environment) {
        // The command and the elevating words read once: what is checked is what runs
        const snapshot = CommandRules.argvSnapshot(givenCommand, true);
        if (snapshot.problem !== "") {
            done?.({ ok: false, code: -1, dismissed: false, refused: false, notFound: false, lines: [], error: "not a command" });
            return;
        }
        const command = snapshot.argv;
        const label = String(what ?? command[0]);
        const refuseRun = problem => {
            console.warn("[Modules] PrivilegedAction refused " + JSON.stringify(label.slice(0, 100)) + ": " + problem);
            if (root.notifyFailures)
                Notifier.send(label + " failed", { body: problem });
            done?.({ ok: false, code: -1, dismissed: false, refused: false, notFound: false, lines: [], error: problem });
        };
        // Taken here, where the module's code called: whose rule this run is under, and whose
        // run it is (for the log)
        const stack = new Error().stack;
        const rule = Modules.host.testMode ? Modules.host.testCallRule(stack) : "strict";
        const callers = ModuleRules.stackDirectories(stack, Modules.host.directories);
        const moduleId = _idOf(callers[0]);
        const givenElevate = elevate;
        const elevateSnapshot = CommandRules.argvSnapshot(givenElevate, false);
        const elevating = elevateSnapshot.argv ?? (Array.isArray(givenElevate) ? Array.from(givenElevate) : givenElevate);
        const testProblem = ModuleRules.testElevateProblem(elevating, Modules.host.testMode, Modules.host.testStandIns, rule);
        if (testProblem !== "") {
            refuseRun(testProblem);
            return;
        }
        if (elevateSnapshot.problem !== "") {
            refuseRun("elevate is not a list of words: " + elevateSnapshot.problem);
            return;
        }
        const request = { command: command, label: label, done: done ?? null, environment: environment ?? {}, elevating: elevating,
                          systemPkexec: PrivilegedRules.legacySystemPkexec(elevating, Modules.host.testMode), moduleId: moduleId };
        if (!command[0].startsWith("/")) {
            _notFound(request, command[0] + " is not an absolute path (pkexec needs one)");
            return;
        }
        // (1.36) Only from one module's own code (the stack names its directory alone), with
        // its manifest's `privileged` block, approved, and command[0] one of the declared,
        // trusted programs as its handle has them — refused before any prompt, the reason in
        // the module's status (PrivilegedRules.callerProblem, legacyDeclarationProblem)
        const handle = moduleId !== "" ? Modules.host.handle(moduleId) : null;
        const crossing = PrivilegedRules.callerProblem(callers, callers[0] ?? "");
        const undeclared = crossing !== "" ? crossing : PrivilegedRules.legacyDeclarationProblem(moduleId,
            handle ? Modules.host.privilegedDeclaration(moduleId, handle.programs) : null, command[0]);
        if (undeclared !== "") {
            if (moduleId !== "")
                Modules.host.reportError(moduleId, undeclared);
            else if (root._untracedWarned !== label)
                console.warn("[Modules] PrivilegedAction refused " + JSON.stringify(label.slice(0, 100)) + ": " + undeclared);
            root._untracedWarned = moduleId === "" ? label : root._untracedWarned;
            done?.({ ok: false, code: -1, dismissed: false, refused: false, notFound: false, blocked: "undeclared", lines: [], error: undeclared });
            return;
        }
        // (1.36) Only "pkexec" (test mode: the stand-in) as the elevating word — more words would
        // run a program of their own as root (PrivilegedRules.legacyElevateProblem)
        const elevateProblem = PrivilegedRules.legacyElevateProblem(elevating, Modules.host.testMode);
        if (elevateProblem !== "") {
            if (moduleId !== "")
                Modules.host.reportError(moduleId, elevateProblem);
            refuseRun(elevateProblem);
            return;
        }
        if (!Modules.host.testMode || rule !== "legacy") {
            _enqueue(request);
            return;
        }
        // The gate (removed by slice Z): the elevating program checked first, never the real
        // pkexec; only then may this object's runs start it
        // The probe's own tools and where a system's pkexec is come from the distribution's
        // facts: looked at once it has answered; not known, the probe is not run (no answer:
        // taken for the real pkexec)
        Distribution.whenReady(() => {
            const toolPath = ModuleRules.probeToolPath(Distribution.facts);
            const verdict = probe => {
                const problem = ModuleRules.testElevateVerdict(probe.ok, probe.lines);
                if (problem !== "") {
                    refuseRun(problem);
                    return;
                }
                if (!root._checkedElevate.includes(elevating[0]))
                    root._checkedElevate = root._checkedElevate.concat([elevating[0]]);
                root._enqueue(request);
            };
            if (toolPath === "") {
                verdict({ ok: false, lines: [] });
                return;
            }
            _probe.run([ModuleRules.probeShell, "-c", ModuleRules.testElevateProbeScript, "sh", elevating[0],
                        PrivilegedRules.pkexecSearchPath(Distribution.facts)].concat(ModuleRules.systemPkexecPaths(Distribution.shipped)),
                       verdict, { PATH: toolPath });
        });
    }

    // Test mode, the gate: the elevating programs the probe found to be stand-ins (REMOVED IN
    // SLICE Z with the gate)
    property var _checkedElevate: []

    // The last run refused for want of a module, logged once while it repeats
    property string _untracedWarned: ""

    // This object's runs, one at a time: the one in the shell's queue, and those after it
    property var _queue: []
    property var _current: null
    property string _ownerKey: ""

    // The id of the module in `directory` ("" for none)
    function _idOf(directory) {
        return directory ? (Modules.host.statuses.find(status => status.directory === directory)?.id ?? "") : "";
    }

    function _notFound(request, reason) {
        if (root.notifyFailures)
            Notifier.send(request.label + " failed", { body: reason });
        request.done?.({ ok: false, code: -1, dismissed: false, refused: false, notFound: true, lines: [], error: reason });
    }

    function _enqueue(request) {
        _queue = _queue.concat([request]);
        _next();
    }

    function _next() {
        if (_current !== null || _queue.length === 0)
            return;
        const request = _queue[0];
        _queue = _queue.slice(1);
        _current = request;
        if (_ownerKey === "")
            _ownerKey = PrivilegedRuns.newOwnerKey();
        PrivilegedRuns.startLegacy({
            owner: _ownerKey, argv: request.elevating.concat(request.command), systemPkexec: request.systemPkexec, program: request.command[0],
            environment: request.environment, testMode: Modules.host.testMode,
            standIns: Modules.host.testStandIns.concat(root._checkedElevate),
            moduleId: request.moduleId, what: request.label
        }, reply => {
            root._current = null;
            root._answered(request, reply);
            Qt.callLater(root._next);
        });
    }

    function _answered(request, reply) {
        const label = request.label;
        switch (reply.kind) {
        case "notFound":
            _notFound(request, request.command[0] + " is not there, or not an executable file");
            return;
        case "locked":
            request.done?.({ ok: false, code: -1, dismissed: true, refused: false, notFound: false, blocked: "locked", lines: [], error: reply.error });
            return;
        case "cancelled":
            request.done?.({ ok: false, code: -1, dismissed: false, refused: false, notFound: false, lines: [], error: "cancelled" });
            return;
        case "refused":
            console.warn("[Modules] PrivilegedAction refused " + JSON.stringify(label.slice(0, 100)) + ": " + reply.error);
            if (root.notifyFailures)
                Notifier.send(label + " failed", { body: reply.error });
            request.done?.({ ok: false, code: -1, dismissed: false, refused: false, notFound: false, lines: [], error: reply.error });
            return;
        }
        const result = reply.result ?? {};
        const error = reply.errorText.trim() || result.error || (result.failedToStart ? "the program could not be started" : "");
        const answer = { ok: result.ok === true, code: result.code ?? -1, lines: reply.lines, error: error,
                         dismissed: result.code === 126, refused: result.code === 127, notFound: false };
        if (answer.refused)
            PrivilegedRuns.reportDenied(label);
        else if (!answer.ok && !answer.dismissed && root.notifyFailures)
            Notifier.send(label + " failed", { body: error || ("Exit code " + answer.code) });
        request.done?.(answer);
    }

    property Io.CommandAction _probe: Io.CommandAction {}

    Component.onDestruction: {
        if (_ownerKey !== "")
            PrivilegedRuns.ownerGone(_ownerKey);
    }
}
