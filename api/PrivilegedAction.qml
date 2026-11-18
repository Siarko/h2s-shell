import QtQuick
import qs.singletons
import qs.singletons.io as Io

// A command run as root through pkexec, the shell's way (module API 1.0; 1.2: an absolute
// path, checked first) — polkit asks for the password through the shell's own prompt or
// whichever agent runs:
//
//   PrivilegedAction { id: admin }
//   admin.run(["/run/current-system/sw/bin/tailscale", "up"], "Connecting Tailscale", result => { … })
//
// run(command, what, done, environment) queues `pkexec <command…>` (one at a time) and calls
// done({ ok, code, dismissed, refused, notFound, lines, error }):
//   ok         it ran and exited 0
//   notFound   (1.2) command[0] is not an absolute path to an executable regular file —
//              checked BEFORE pkexec is asked, so a missing program never shows as "not
//              authorised": a plain failure, notified as "<what> failed" with the reason
//              (unless notifyFailures is false); pkexec is not run, nothing is denied
//   dismissed  pkexec exited 126: the prompt was dismissed or the password not accepted —
//              nothing is shown (the user chose it); put the state back
//   refused    pkexec exited 127: not authorised, or no authentication agent answered — the
//              shell says so once, with the way out (Authentication.reportDenied(what))
//   otherwise  the command itself failed: notified as "<what> failed" with its error, unless
//              notifyFailures is false (a VPN provider emits failed() instead)
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

    // What runs the command as root: pkexec (a module's suites put a stand-in here)
    property var elevate: ["pkexec"]
    // "<what> failed" notifications for a command that ran and failed
    property bool notifyFailures: true
    readonly property bool busy: _action.busy || _probe.busy

    function run(command, what, done, environment) {
        if (!Array.isArray(command) || command.length === 0 || command.some(part => typeof part !== "string")) {
            done?.({ ok: false, code: -1, dismissed: false, refused: false, notFound: false, lines: [], error: "not a command" });
            return;
        }
        const label = String(what ?? command[0]);
        const notFound = reason => {
            const answer = { ok: false, code: -1, dismissed: false, refused: false, notFound: true, lines: [], error: reason };
            if (root.notifyFailures)
                Notifier.send(label + " failed", { body: reason });
            done?.(answer);
        };
        const testRefused = problem => {
            console.warn("[Modules] PrivilegedAction refused " + JSON.stringify(label.slice(0, 100)) + ": " + problem);
            if (root.notifyFailures)
                Notifier.send(label + " failed", { body: problem });
            done?.({ ok: false, code: -1, dismissed: false, refused: false, notFound: false, lines: [], error: problem });
        };
        // Taken here, where the module's code called: whose rule this run is under
        const rule = Modules.host.testMode ? Modules.host.testCallRule(new Error().stack) : "strict";
        const elevating = Array.isArray(elevate) ? Array.from(elevate) : elevate;
        const testProblem = ModuleRules.testElevateProblem(elevating, Modules.host.testMode, Modules.host.testStandIns, rule);
        if (testProblem !== "") {
            testRefused(testProblem);
            return;
        }
        if (!command[0].startsWith("/")) {
            notFound(command[0] + " is not an absolute path (pkexec needs one)");
            return;
        }
        const runIt = () => {
            // The program first: an executable regular file (no shell sees the path: it is $1)
            _probe.run(["sh", "-c", "[ -f \"$1\" ] && [ -x \"$1\" ]", "sh", command[0]], probe => {
                if (!probe.ok) {
                    notFound(command[0] + " is not there, or not an executable file");
                    return;
                }
                _action.run(elevating.concat(command), result => {
                    const answer = Object.assign({}, result, { dismissed: result.code === 126, refused: result.code === 127, notFound: false });
                    if (answer.refused)
                        Authentication.reportDenied(label);
                    else if (!answer.ok && !answer.dismissed && root.notifyFailures)
                        Notifier.send(label + " failed", { body: result.error || ("Exit code " + result.code) });
                    done?.(answer);
                }, environment ?? {});
            }, {});
        };
        if (!Modules.host.testMode || rule !== "legacy") {
            runIt();
            return;
        }
        // The gate (removed by slice Z): the elevating program checked first, never the real
        // pkexec; only then may this object's runs start it
        _probe.run([ModuleRules.probeShell, "-c", ModuleRules.testElevateProbeScript, "sh", elevating[0], ModuleRules.testPkexecLookupPath]
                   .concat(ModuleRules.systemPkexecPaths), probe => {
            const problem = ModuleRules.testElevateVerdict(probe.ok, probe.lines);
            if (problem !== "") {
                testRefused(problem);
                return;
            }
            if (!root._checkedElevate.includes(elevating[0]))
                root._checkedElevate = root._checkedElevate.concat([elevating[0]]);
            runIt();
        }, { PATH: ModuleRules.probeToolPath });
    }

    // Test mode, the gate: the elevating programs the probe found to be stand-ins (REMOVED IN
    // SLICE Z with the gate)
    property var _checkedElevate: []

    property Io.CommandAction _action: Io.CommandAction {
        refuse: function (argv) {
            return ModuleRules.testRunProblem(argv, Modules.host.testMode, Modules.host.testStandIns.concat(root._checkedElevate));
        }
    }
    property Io.CommandAction _probe: Io.CommandAction {}
}
