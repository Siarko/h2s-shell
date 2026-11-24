import QtQuick
import Quickshell
import qs.distributions
import qs.singletons
import qs.singletons.io

// Apply and Undo of the PAM rules on Arch (ArchIntegration's writer of "pam.rules", which
// Integration's apply and undo hand the change to): one run as administrator per service, the root
// step's files (PamApplyRules.scriptFiles, in scripts/root/) read from the shell's tree at the
// click and their text run by the system's /bin/sh — never run by path. Apply follows a passed
// trial (the user's click on Apply started both); Undo is a click of its own. What may run and
// what the answer means are PamApplyRules'; the run is EtcFiles' (queued, the service's file
// read again as the user when the run did not say it was done — a run cut short may still
// have changed it); this hands the outcome over. One run at a time.
//
// `start` is what queues the run: null for the shell's runs as administrator
// (PrivilegedRuns.startShell, which says who asks and what for), and then only the system's
// places (PamApplyRules.livePaths); a suite's stand-in (which runs the same words as the
// user) only with places under a scratch folder outside /etc, /usr and /var
// (PamApplyRules.pathsRefusal).
QtObject {
    id: root

    // After each started run: PamApplyRules.applyReply's outcome; when not ok, its `file`
    // is PamApplyRules.afterFailure's answer for the file read again. The run's own
    // `handlers.done`, when given, has it first
    signal finished(var outcome)

    // (request { what, argv }, done(result)) → nothing; done once with PrivilegedRules' result
    property var start: null
    property var paths: PamApplyRules.livePaths
    property string shell: "/bin/sh"
    property var filesCommand: [Quickshell.shellDir + "/scripts/pam-files.sh"]
    // Where the root step's files are (scripts/root/ of the shell's tree), read at each run
    property string scriptsDirectory: Quickshell.shellDir + "/" + RootScriptRules.directory
    readonly property bool busy: _files.busy

    // Apply one service's new rules. `request`: PamApplyRules.applyArgv's (service, built,
    // currentText, vendorText, trial); `handlers` { done (outcome → nothing, once) }. →
    // { started, refusal (null or { code, text }) }
    function apply(request, handlers) {
        return _run(PamApplyRules.applyArgv(shell, request, paths, start === null, _scripts.read()), PamApplyRules.what("apply", String(request?.service ?? "")),
                    handlers?.done);
    }

    // Put back what an Apply replaced. `handlers` { from (that Apply's outcome: its service,
    // backup, and sha256 — what it left in force), done }
    function undo(handlers) {
        const from = handlers?.from;
        const request = { service: from?.service, backup: from?.backup, currentSha256: from?.sha256 };
        return _run(PamApplyRules.undoArgv(shell, request, paths, start === null, _scripts.read()), PamApplyRules.what("undo", String(request.service ?? "")),
                    handlers?.done);
    }

    function _run(plan, what, done) {
        if (_files.busy)
            return { started: false, refusal: PamApplyRules.refusal("busy") };
        if (plan.refusal !== null)
            return { started: false, refusal: plan.refusal };
        const path = paths.system + "/" + plan.expected.service;
        const code = _files.run({
            what: what,
            argv: plan.argv,
            reply: result => PamApplyRules.applyReply(result, plan.expected),
            readBack: [path],
            after: (answers, outcome) => outcome.file = PamApplyRules.afterFailure(answers[path], plan.expected),
            done: outcome => {
                try {
                    done?.(outcome);
                } finally {
                    root.finished(outcome);
                }
            }
        });
        return code === "" ? { started: true, refusal: null } : { started: false, refusal: PamApplyRules.refusal(code) };
    }

    // The run itself, and the file read again after a failure
    property EtcFiles _files: EtcFiles {
        start: root.start
        shell: root.shell
        filesCommand: root.filesCommand
    }
    property RootScriptFiles _scripts: RootScriptFiles {
        names: PamApplyRules.scriptFiles
        directory: root.scriptsDirectory
    }
}
