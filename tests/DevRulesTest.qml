import QtQuick
import qs.singletons

// DevRules (pure): development mode from H2S_SHELL_DEV and the launcher's --dev
// (H2S_SHELL_DEV_FLAG), and file watching from it and the lock.
TestCase {
    id: suite
    suiteName: "DevRules"

    function run() {
        // Off by default: nothing set
        assertEqual(DevRules.devMode(undefined, undefined), false, "nothing set: off");
        assertEqual(DevRules.devMode(null, null), false, "null: off");
        assertEqual(DevRules.devMode("", ""), false, "both empty: off");

        // The variable alone
        assertEqual(DevRules.devMode("1", undefined), true, "H2S_SHELL_DEV=1: on");
        assertEqual(DevRules.devMode(" 1\n", undefined), true, "H2S_SHELL_DEV=1 with spaces: on");
        assertEqual(DevRules.devMode("0", undefined), false, "H2S_SHELL_DEV=0: off");

        // The flag alone
        assertEqual(DevRules.devMode(undefined, "1"), true, "--dev: on");
        assertEqual(DevRules.devMode("", "1"), true, "--dev, H2S_SHELL_DEV empty: on");
        assertEqual(DevRules.devMode(undefined, "0"), false, "flag 0: off");
        assertEqual(DevRules.devMode(undefined, "yes"), false, "flag another word: off");

        // The variable decides over the flag
        assertEqual(DevRules.devMode("0", "1"), false, "H2S_SHELL_DEV=0 launch.sh --dev: off");
        assertEqual(DevRules.devMode("1", "0"), true, "H2S_SHELL_DEV=1, flag 0: on");
        assertEqual(DevRules.devMode("1", "1"), true, "both on: on");

        // A variable that says neither leaves it to the flag
        assertEqual(DevRules.devMode("yes", "1"), true, "H2S_SHELL_DEV=yes and --dev: the flag's (on)");
        assertEqual(DevRules.devMode("yes", undefined), false, "H2S_SHELL_DEV=yes alone: off");
        assertEqual(DevRules.devMode("true", undefined), false, "H2S_SHELL_DEV=true alone: off (only 1 and 0 are read)");

        // File watching: development mode, and never while locked
        assertEqual(DevRules.watchFiles(true, false), true, "dev, unlocked: on");
        assertEqual(DevRules.watchFiles(true, true), false, "dev, locked: off");
        assertEqual(DevRules.watchFiles(false, false), false, "not dev, unlocked: off");
        assertEqual(DevRules.watchFiles(false, true), false, "not dev, locked: off");
        assertEqual(DevRules.watchFiles(undefined, undefined), false, "unknown: off");
        assertEqual(DevRules.watchFiles("1", false), false, "dev must be a boolean, not a string");
    }
}
