import QtQuick
import qs.singletons

// The Hibernate section's Apply, on a system where /etc is the machine's own (not NixOS):
// the system's delay before a sleep turns into hibernation written as sleep.conf's drop-in
// (HibernateRules.dropInDirectory/dropInName), by one run as administrator — the user's click
// started it, polkit asks for the password. The command is HibernateRules.applyArgv's fixed
// script, run by the system's /bin/sh; nothing is loaded from a file.
//
// `start` is what queues the run: PrivilegedRuns.startShell, or a reading suite's stand-in
// (which runs the same command as the user, into a scratch `directory`). One write at a time.
QtObject {
    id: root

    // After each apply(): whether the delay was written; `quiet` for a prompt dismissed or a
    // run refused (said elsewhere, or the user's choice); `error` otherwise
    signal applied(int seconds, bool ok, bool quiet, string error)

    property string directory: HibernateRules.dropInDirectory
    property string shell: "/bin/sh"
    // (request { what, argv }, done(result)) → nothing; done once with PrivilegedRules' result
    property var start: (request, done) => PrivilegedRuns.startShell(request, done)
    readonly property bool busy: _busy

    property bool _busy: false

    // → false when not started (one under way, or a delay HibernateRules.applyArgv refuses)
    function apply(seconds) {
        if (_busy)
            return false;
        const argv = HibernateRules.applyArgv(shell, seconds, directory);
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
}
