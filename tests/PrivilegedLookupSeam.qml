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
//   startShell(what, argv, done, detached, extra)
//                         asks for one of the shell's own fixed commands (PrivilegedRuns
//                         .startShell, a setting's Apply). Called straight from a suite's code
//                         (a module's directory on the stack) it is refused before the queue;
//                         `detached`, it is asked from the event loop, as the shell's own code
//                         asks — then queued, and in test mode refused at its launch (no
//                         stand-in is allowed for it), so nothing runs. `extra`: more of the
//                         request (timeoutMs, onLine, and testPkexec: a module's stand-in
//                         pkexec, which then runs in the trusted one's place)
//   lastShellArgv()       the words the last of those was queued with (pkexec still by name)
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

    function startShell(what, argv, done, detached, extra) {
        if (!Modules.host.testMode)
            return;
        const request = Object.assign({}, extra ?? {}, { what: String(what), argv: argv });
        if (detached === true)
            Qt.callLater(() => PrivilegedRuns.startShell(request, done));
        else
            PrivilegedRuns.startShell(request, done);
    }

    function lastShellArgv() {
        return Modules.host.testMode ? Array.from(PrivilegedRuns._lastShellArgv) : [];
    }

    function waitingCount() {
        return Modules.host.testMode ? PrivilegedRuns._waitingForLookup.length : 0;
    }
}
