import QtQuick
import Quickshell
import qs.singletons
import qs.singletons.io

// The root step of applying a NixOS build (scripts/root/nixos-apply.sh): Create of the shell's
// file, Apply of a build (apply or switch, by who owns the configuration), and Undo of a
// failed Apply's write (restore), each one run as administrator started by the user's click.
// The root step's files (NixosApplyRules.scriptFiles, in scripts/root/) are read from the
// shell's tree at the click and their text run by the system's /bin/sh — never run by path.
// What may run and what the answer means are NixosApplyRules'; this starts the run through
// PrivilegedRuns.startShell (what it is for, naming the folder and host; NixosApplyRules
// .timeoutMs; each line of its output handed on as it comes) and hands the outcome over. One
// run at a time. The writer interface of a distribution integration: apply(value, handlers),
// undo(handlers), busy.
//
// The test seams take effect only in module test mode (a fixture suite's): `testPkexec`, a
// stand-in pkexec that PrivilegedRuns runs in the trusted one's place (it runs the same
// words as the user), and then places under a scratch folder outside /etc, /usr and /var
// only; `testShell` and `testScriptsDirectory`, the program run and where the root step's
// files are read. Anywhere else the run is `live`: the system's pkexec, only the system's
// places (NixosApplyRules.livePaths), /bin/sh and the shell's own scripts/root/.
QtObject {
    id: root

    // After each started run: NixosApplyRules.reply's outcome. The run's own `handlers.done`
    // has it first
    signal finished(var outcome)

    property string testPkexec: ""
    property string testShell: ""
    property string testScriptsDirectory: ""
    property var paths: NixosApplyRules.livePaths
    readonly property bool live: !(Modules.host.testMode && testPkexec !== "")
    readonly property string shell: !live && testShell !== "" ? testShell : "/bin/sh"
    // Where the root step's files are (scripts/root/ of the shell's tree), read at each run
    readonly property string scriptsDirectory: !live && testScriptsDirectory !== "" ? testScriptsDirectory
        : Quickshell.shellDir + "/" + RootScriptRules.directory
    readonly property bool busy: _running

    property bool _running: false

    // `value` { op ("create" | "apply"), reading (NixosConfigRules.reading's, as the user saw
    // it), candidate (for apply: { text, sha256, drvPath, outPath }) }; `handlers` { done
    // (outcome → nothing, once), onLine ((line, stream) for each line of the run's output) }
    // → { started, refusal (null or { code, text }) }
    function apply(value, handlers) {
        return _run({ op: value?.op, reading: value?.reading, candidate: value?.candidate }, handlers);
    }

    // Put back the shell's file a failed Apply wrote. `handlers` { from (that Apply's outcome:
    // its folder, backup and sha256), reading (the configuration as read now), done, onLine }
    function undo(handlers) {
        return _run({ op: "restore", reading: handlers?.reading, from: handlers?.from }, handlers);
    }

    function _run(request, handlers) {
        if (_running)
            return { started: false, refusal: NixosApplyRules.refusal("running") };
        const plan = NixosApplyRules.plan(request, paths, live, _scripts.read(), shell);
        if (plan.refusal !== null)
            return { started: false, refusal: plan.refusal };
        const done = handlers?.done;
        const onLine = handlers?.onLine;
        const startRequest = {
            what: plan.what,
            argv: plan.argv,
            timeoutMs: NixosApplyRules.timeoutMs,
            onLine: (line, stream) => {
                if (typeof onLine === "function")
                    onLine(line, stream);
            }
        };
        if (!live)
            startRequest.testPkexec = testPkexec;
        _running = true;
        PrivilegedRuns.startShell(startRequest, result => {
            const outcome = NixosApplyRules.reply(result, plan.expected);
            root._running = false;
            try {
                if (typeof done === "function")
                    done(outcome);
            } finally {
                root.finished(outcome);
            }
        });
        return { started: true, refusal: null };
    }

    property RootScriptFiles _scripts: RootScriptFiles {
        names: NixosApplyRules.scriptFiles
        directory: root.scriptsDirectory
    }
}
