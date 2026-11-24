import QtQuick
import Quickshell
import qs.distributions
import qs.singletons
import qs.singletons.io

// Install, Remove and Undo of the VPN blocking's script and its polkit rule on Arch
// (ArchIntegration's writer of "network.vpnLockdown", which Integration's apply and undo hand
// the change to): one run as administrator each, started by the user's click, the root step's
// files (VpnLockdownInstallRules.scriptFiles, in scripts/root/) read from the shell's tree at
// the click and their text run by the system's /bin/sh — never run by path. What may run and
// what the answer means are VpnLockdownInstallRules'; the run is EtcFiles' (queued, the two
// files read again as the user when the run did not say it was done); this hands the outcome
// over. One run at a time.
//
// `start` is what queues the run: null for the shell's runs as administrator
// (PrivilegedRuns.startShell, which says who asks and what for), and then only the system's
// places (VpnLockdownInstallRules.livePaths); a suite's stand-in (which runs the same words as
// the user) only with places under a scratch folder outside /etc, /usr and /var.
QtObject {
    id: root

    // After each started run: VpnLockdownInstallRules.reply's outcome (with `op`); when not
    // ok, its `files` is afterFailure's answer for the files read again. The run's own
    // `handlers.done` has it first
    signal finished(var outcome)

    // (request { what, argv }, done(result)) → nothing; done once with PrivilegedRules' result
    property var start: null
    property var paths: VpnLockdownInstallRules.livePaths
    property string shell: "/bin/sh"
    property var filesCommand: [Quickshell.shellDir + "/scripts/pam-files.sh"]
    // Where the root step's files are (scripts/root/ of the shell's tree), read at each run
    property string scriptsDirectory: Quickshell.shellDir + "/" + RootScriptRules.directory
    readonly property bool busy: _files.busy

    // `value` { op ("install" | "remove"), user, script, current, replace }:
    // VpnLockdownInstallRules.installArgv's or removeArgv's request; `handlers` { done } →
    // { started, refusal }
    function apply(value, handlers) {
        const remove = value?.op === "remove";
        const plan = remove ? VpnLockdownInstallRules.removeArgv(shell, value, paths, start === null, _scripts.read())
                            : VpnLockdownInstallRules.installArgv(shell, value, paths, start === null, _scripts.read());
        return _run(plan, VpnLockdownInstallRules.what(remove ? "remove" : "install"), remove ? "remove" : "install", handlers?.done);
    }

    // Put back what a run changed. `handlers` { from (that run's outcome: its stamp and what it
    // left), done }
    function undo(handlers) {
        const from = handlers?.from;
        const request = { stamp: from?.stamp, script: from?.script, rule: from?.rule };
        return _run(VpnLockdownInstallRules.undoArgv(shell, request, paths, start === null, _scripts.read()),
                    VpnLockdownInstallRules.what("undo"), "undo", handlers?.done);
    }

    function _run(plan, what, op, done) {
        if (_files.busy)
            return { started: false, refusal: VpnLockdownInstallRules.refusal("busy") };
        if (plan.refusal !== null)
            return { started: false, refusal: plan.refusal };
        const code = _files.run({
            what: what,
            argv: plan.argv,
            reply: result => Object.assign(VpnLockdownInstallRules.reply(result, plan.expected), { op }),
            readBack: [paths.script, paths.rule],
            after: (answers, outcome) => outcome.files = VpnLockdownInstallRules.afterFailure({ script: answers[paths.script], rule: answers[paths.rule] }, plan.expected),
            done: outcome => {
                try {
                    done?.(outcome);
                } finally {
                    root.finished(outcome);
                }
            }
        });
        return code === "" ? { started: true, refusal: null } : { started: false, refusal: VpnLockdownInstallRules.refusal(code) };
    }

    property EtcFiles _files: EtcFiles {
        start: root.start
        shell: root.shell
        filesCommand: root.filesCommand
    }
    property RootScriptFiles _scripts: RootScriptFiles {
        names: VpnLockdownInstallRules.scriptFiles
        directory: root.scriptsDirectory
    }
}
