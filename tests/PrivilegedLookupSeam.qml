pragma Singleton

import Quickshell
import QtQuick
import qs.singletons

// For the shell's own fixture suites only (tests/fixtures/modules/privileged), not part of
// what a module's suites get (ModuleTestKit): the old PrivilegedAction's runs that name the
// shell's trusted pkexec, and its look-up of pkexec held, in module test mode.
//
//   holdLookup(on)        the look-up of pkexec held, as if it had not answered yet;
//                         released, it answers with what it found
//   startTrusted(what, program, answer)
//                         queues a run as PrivilegedAction's default elevate ("pkexec" by
//                         name) queues it outside test mode: argv[0] is replaced by the
//                         trusted pkexec when it launches. No stand-in is allowed, so the
//                         test-mode check (ModuleRules.testRunProblem) refuses it at launch
//                         and nothing runs: answer({ kind: "refused" }). → its owner key
//   waitingCount()        how many runs wait in their check for the look-up
//   startShell(what, argv, done)
//                         queues one of the shell's own fixed commands (PrivilegedRuns
//                         .startShell, a setting's Apply): no stand-in is allowed for it, so
//                         in test mode it is refused at its launch and nothing runs
// All of them do nothing outside test mode.
Singleton {
    function holdLookup(on) {
        if (Modules.host.testMode)
            PrivilegedRuns.testLookupHeld = on === true;
    }

    function startTrusted(what, program, answer) {
        if (!Modules.host.testMode)
            return "";
        const owner = PrivilegedRuns.newOwnerKey();
        PrivilegedRuns.startLegacy({
            owner: owner, argv: ["pkexec", String(program)], systemPkexec: true, program: String(program),
            environment: {}, standIns: [], testMode: true, moduleId: "privileged", what: String(what)
        }, answer);
        return owner;
    }

    function startShell(what, argv, done) {
        if (Modules.host.testMode)
            PrivilegedRuns.startShell({ what: String(what), argv: argv }, done);
    }

    function waitingCount() {
        return Modules.host.testMode ? PrivilegedRuns._waitingForLookup.length : 0;
    }
}
