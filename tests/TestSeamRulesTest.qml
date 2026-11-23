import QtQuick
import qs.tests.lock.seams as TestBed

// The test seams (tests/lock/seams/TestSeamRules.qml, read by the test tree's TestSeams):
// what each variable says, what is in force and what is ignored. That the production
// TestSeams reads none of them, and that no file of the shell reads one itself:
// TestSeamsShapeTest.
TestCase {
    id: suite
    suiteName: "TestSeamRules"

    function run() {
        const TestSeamRules = TestBed.TestSeamRules;
        const read = TestSeamRules.read;
        const none = read({});
        assertEqual(none.inForce.length + none.ignored.length, 0, "nothing set: no seam in force, none ignored");
        assertEqual([none.lockTools, none.systemPamDirectory, none.ledsDirectory, none.moduleCheckPath, none.distribution].join("|"), "||||",
                    "nothing set: no directory");
        assert(!none.reloadIpc && !none.moduleNotify && !none.fakeVpnProvider && none.moduleGuardMs === 0 && none.moduleCheckMs === 0
               && JSON.stringify(none.timings) === "{}" && none.timingsProblem === "", "nothing set: nothing changed");
        assert(Object.isFrozen(none) && Object.isFrozen(none.inForce), "frozen");
        assertEqual(JSON.stringify(read(null).inForce), "[]", "no environment at all: nothing");

        // What the lock bed sets (tests/lock/lib.sh)
        const bed = read({ H2S_LOCK_TOOLS: "/w/tools", H2S_LOCK_SYSTEM_PAM_DIR: "/w/pam",
                           H2S_LOCK_LEDS_DIR: "/w/leds", H2S_LOCK_TEST_TIMINGS: "{\"roundMs\":4000}", H2S_LOCK_TEST_RELOAD: "1",
                           H2S_SHELL_TEST_MODULE_GUARD_MS: "3000", H2S_SHELL_TEST_MODULE_CHECK_PATH: "/w/hung",
                           H2S_SHELL_TEST_MODULE_CHECK_MS: "800", H2S_SHELL_TEST_MODULE_NOTIFY: "1", H2S_FAKE_VPN_PROVIDER: "1",
                           H2S_DISTRIBUTION: "nixos", H2S_DISTRIBUTION_HOLD: "/w/hold" });
        assertEqual(bed.inForce.join(","), TestSeamRules.names.join(","), "all set: all in force, in the list's order");
        assertEqual([bed.lockTools, bed.systemPamDirectory, bed.ledsDirectory, bed.moduleCheckPath].join("|"),
                    "/w/tools|/w/pam|/w/leds|/w/hung", "the directories as given");
        assertEqual(JSON.stringify(bed.timings), "{\"roundMs\":4000}", "the timings as given");
        assert(bed.reloadIpc && bed.moduleNotify && bed.fakeVpnProvider && bed.moduleGuardMs === 3000 && bed.moduleCheckMs === 800, "the switches and numbers");
        assertEqual(bed.distribution + " " + bed.distributionHold, "nixos /w/hold", "the distribution and its hold as given");
        assertEqual(read({ H2S_DISTRIBUTION: "nixos" }).distribution, "", "a distribution without the PAM directory: none (as the scripts count it)");

        // Values the shell cannot use: not in force, named as ignored
        const bad = read({ H2S_LOCK_TEST_TIMINGS: "{oops", H2S_LOCK_TEST_RELOAD: "yes",
                           H2S_SHELL_TEST_MODULE_GUARD_MS: "-5", H2S_SHELL_TEST_MODULE_CHECK_PATH: "relative/dir",
                           H2S_SHELL_TEST_MODULE_CHECK_MS: "Infinity", H2S_SHELL_TEST_MODULE_NOTIFY: "yes", H2S_FAKE_VPN_PROVIDER: "true",
                           H2S_DISTRIBUTION: "Arch Linux", H2S_DISTRIBUTION_HOLD: "relative/hold" });
        assertEqual(bad.inForce.length, 0, "unusable values: none in force");
        assertEqual(bad.ignored.join(","), "H2S_LOCK_TEST_TIMINGS,H2S_LOCK_TEST_RELOAD,H2S_SHELL_TEST_MODULE_GUARD_MS,"
                    + "H2S_SHELL_TEST_MODULE_CHECK_PATH,H2S_SHELL_TEST_MODULE_CHECK_MS,H2S_SHELL_TEST_MODULE_NOTIFY,H2S_FAKE_VPN_PROVIDER,H2S_DISTRIBUTION,H2S_DISTRIBUTION_HOLD", "… each named as ignored");
        assertEqual(bad.timingsProblem, "not JSON", "timings that are not JSON: said so");
        assertEqual(JSON.stringify(bad.timings), "{}", "… and none taken");
        assertEqual(read({ H2S_LOCK_TEST_TIMINGS: "[1]" }).timingsProblem, "not a JSON object", "timings that are a list: not an object");
        assertEqual(bad.distribution, "", "a distribution that is no identifier: none");
        assertEqual(read({ H2S_LOCK_TOOLS: 5 }).lockTools, "", "a value that is no text: not set");
    }
}
