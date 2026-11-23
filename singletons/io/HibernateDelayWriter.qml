import QtQuick
import Quickshell
import qs.singletons

// The Hibernate section's Apply, on a system where /etc is the machine's own (not NixOS):
// the system's delay before a sleep turns into hibernation written as sleep.conf's drop-in
// (HibernateRules.dropInDirectory/dropInName), by one run as administrator — the user's click
// started it, polkit asks for the password. The root step is HibernateRules.scriptFiles (in
// scripts/root/), read from the shell's tree at the click and its text run by the system's
// /bin/sh; never run by path.
//
// `start` is what queues the run: PrivilegedRuns.startShell, or a reading suite's stand-in
// (which runs the same command as the user, under a scratch `base`). One write at a time.
QtObject {
    id: root

    // After each apply(): whether the delay was written; `quiet` for a prompt dismissed or a
    // run refused (said elsewhere, or the user's choice); `error` otherwise
    signal applied(int seconds, bool ok, bool quiet, string error)

    // The folder the drop-in's place is under: "" for the system (a suite: a scratch folder)
    property string base: ""
    property string shell: "/bin/sh"
    // Where the root step's file is (scripts/root/ of the shell's tree), read at each Apply
    property string scriptsDirectory: Quickshell.shellDir + "/" + RootScriptRules.directory
    // (request { what, argv }, done(result)) → nothing; done once with PrivilegedRules' result
    property var start: (request, done) => PrivilegedRuns.startShell(request, done)
    readonly property bool busy: _busy

    property bool _busy: false

    // → false when not started (one under way, a delay HibernateRules.applyArgv refuses, or
    // the script not read: said in the log)
    function apply(seconds) {
        if (_busy)
            return false;
        const scripts = _scripts.read();
        if (RootScriptRules.script(scripts) === "") {
            console.warn("[HibernateDelayWriter] the shell's script could not be read: " + scriptsDirectory + "/" + HibernateRules.scriptFiles.join(", "));
            return false;
        }
        const argv = HibernateRules.applyArgv(shell, seconds, base, scripts);
        if (argv === null)
            return false;
        _busy = true;
        start({ what: "Change the time before hibernating", argv: argv }, result => {
            root._busy = false;
            const outcome = HibernateRules.applyOutcome(result, seconds);
            root.applied(seconds, outcome.ok, outcome.quiet, outcome.error);
        });
        return true;
    }

    property RootScriptFiles _scripts: RootScriptFiles {
        names: HibernateRules.scriptFiles
        directory: root.scriptsDirectory
    }
}
