import QtQuick
import Quickshell
import qs.singletons
import qs.distributions.nixos

// distributions/nixos/NixosApply.qml outside module test mode: its test seams take no effect
// there — the shell is the system's /bin/sh, the root step's files the shell's own
// scripts/root/, the run the system's pkexec (only livePaths) — and none can be set from
// outside (tests/fixtures/modules/nixos-apply runs it on a stand-in, in test mode)
TestCase {
    suiteName: "NixosApplyLive"

    property NixosApply writer: NixosApply {
        testPkexec: "/tmp/stand-in/pkexec"
        testShell: "/tmp/stand-in/sh"
        testScriptsDirectory: "/tmp/stand-in/scripts"
    }

    function run() {
        assert(!Modules.host.testMode, "not module test mode");
        assertEqual(writer.shell, "/bin/sh", "the shell: the system's, whatever a test seam says");
        assertEqual(writer.scriptsDirectory, Quickshell.shellDir + "/scripts/root", "the root step's files: the shell's own");
        assertEqual(writer.live, true, "the run: the system's pkexec, so only the system's places");
        for (const name of ["shell", "scriptsDirectory", "live"]) {
            let threw = false;
            try {
                writer[name] = "/tmp/other";
            } catch (error) {
                threw = true;
            }
            assert(threw, name + ": not settable from outside");
        }
        // The system's places for the system's pkexec: refused only by what the reading lacks
        const refused = writer.apply({ op: "create", reading: null }, {});
        assertEqual(JSON.stringify(refused), JSON.stringify({ started: false, refusal: NixosApplyRules.refusal("notFound") }),
                    "live: the system's places taken, nothing started without a configuration");
        writer.paths = { bin: "/tmp/x" + NixosApplyRules.livePaths.bin, profile: "/tmp/x" + NixosApplyRules.livePaths.profile,
                         store: "/tmp/x" + NixosApplyRules.livePaths.store, backups: "/tmp/x" + NixosApplyRules.livePaths.backups };
        assertEqual(writer.apply({ op: "create", reading: null }, {}).refusal.code, "paths", "live: scratch places refused");
        writer.paths = NixosApplyRules.livePaths;
    }
}
