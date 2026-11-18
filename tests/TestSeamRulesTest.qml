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
        assertEqual([none.lockTools, none.systemPamDirectory, none.lockSystem, none.ledsDirectory, none.moduleCheckPath].join("|"), "||||",
                    "nothing set: no directory");
        assert(!none.reloadIpc && !none.fakeVpnProvider && none.moduleGuardMs === 0 && none.moduleCheckMs === 0
               && JSON.stringify(none.timings) === "{}" && none.timingsProblem === "", "nothing set: nothing changed");
        assert(Object.isFrozen(none) && Object.isFrozen(none.inForce), "frozen");
        assertEqual(JSON.stringify(read(null).inForce), "[]", "no environment at all: nothing");

        // What the lock bed sets (tests/lock/lib.sh)
        const bed = read({ H2S_LOCK_TOOLS: "/w/tools", H2S_LOCK_SYSTEM_PAM_DIR: "/w/pam", H2S_LOCK_SYSTEM: "nixos",
                           H2S_LOCK_LEDS_DIR: "/w/leds", H2S_LOCK_TEST_TIMINGS: "{\"roundMs\":4000}", H2S_LOCK_TEST_RELOAD: "1",
                           H2S_SHELL_TEST_MODULE_GUARD_MS: "3000", H2S_SHELL_TEST_MODULE_CHECK_PATH: "/w/hung",
                           H2S_SHELL_TEST_MODULE_CHECK_MS: "800", H2S_FAKE_VPN_PROVIDER: "1" });
        assertEqual(bed.inForce.join(","), TestSeamRules.names.join(","), "all set: all in force, in the list's order");
        assertEqual([bed.lockTools, bed.systemPamDirectory, bed.lockSystem, bed.ledsDirectory, bed.moduleCheckPath].join("|"),
                    "/w/tools|/w/pam|nixos|/w/leds|/w/hung", "the directories and the system as given");
        assertEqual(JSON.stringify(bed.timings), "{\"roundMs\":4000}", "the timings as given");
        assert(bed.reloadIpc && bed.fakeVpnProvider && bed.moduleGuardMs === 3000 && bed.moduleCheckMs === 800, "the switches and numbers");

        // Values the shell cannot use: not in force, named as ignored
        const bad = read({ H2S_LOCK_SYSTEM: "nixos", H2S_LOCK_TEST_TIMINGS: "{oops", H2S_LOCK_TEST_RELOAD: "yes",
                           H2S_SHELL_TEST_MODULE_GUARD_MS: "-5", H2S_SHELL_TEST_MODULE_CHECK_PATH: "relative/dir",
                           H2S_SHELL_TEST_MODULE_CHECK_MS: "Infinity", H2S_FAKE_VPN_PROVIDER: "true" });
        assertEqual(bad.inForce.length, 0, "unusable values: none in force");
        assertEqual(bad.ignored.join(","), "H2S_LOCK_SYSTEM,H2S_LOCK_TEST_TIMINGS,H2S_LOCK_TEST_RELOAD,H2S_SHELL_TEST_MODULE_GUARD_MS,"
                    + "H2S_SHELL_TEST_MODULE_CHECK_PATH,H2S_SHELL_TEST_MODULE_CHECK_MS,H2S_FAKE_VPN_PROVIDER", "… each named as ignored");
        assertEqual(bad.lockSystem, "", "a system without the PAM directory: none (LockIoRules.systemSeam's rule)");
        assertEqual(bad.timingsProblem, "not JSON", "timings that are not JSON: said so");
        assertEqual(JSON.stringify(bad.timings), "{}", "… and none taken");
        assertEqual(read({ H2S_LOCK_TEST_TIMINGS: "[1]" }).timingsProblem, "not a JSON object", "timings that are a list: not an object");
        assertEqual(read({ H2S_LOCK_SYSTEM_PAM_DIR: "/p", H2S_LOCK_SYSTEM: "windows" }).lockSystem, "", "a system that is neither nixos nor other: none");
        assertEqual(read({ H2S_LOCK_TOOLS: 5 }).lockTools, "", "a value that is no text: not set");
    }
}
