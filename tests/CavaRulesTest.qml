import QtQuick
import qs.singletons

// What a run of cava came to, when it is tried again, and what is logged
TestCase {
    suiteName: "CavaRules"

    function run() {
        const loader = "cava: error while loading shared libraries: libsndio.so.7: cannot open shared object file";
        assertEqual(CavaRules.problem(true, 127, false, [loader]), "cava exited with code 127: " + loader,
            "problem: the exit code and the first line it said");
        assertEqual(CavaRules.problem(true, 1, false, ["", "  second  ", "third"]), "cava exited with code 1: second",
            "problem: the first line that says something, trimmed");
        assertEqual(CavaRules.problem(true, 0, false, []), "cava exited with code 0", "problem: nothing said, the code alone");
        assertEqual(CavaRules.problem(false, -1, false, []), "cava could not be started", "problem: no exit status");
        assertEqual(CavaRules.problem(true, 11, true, ["boom"]), "cava crashed: boom", "problem: a crash");
        assertEqual(CavaRules.problem(true, 1, false, ["a\tb\u001bc"]), "cava exited with code 1: a b c", "problem: control characters made spaces");
        assertEqual(CavaRules.problem(true, 1, false, ["x".repeat(500)]).length, "cava exited with code 1: ".length + 200,
            "problem: what it said capped");

        assertEqual(CavaRules.retryDelay(1, 2000, 60000), 2000, "retryDelay: the first try after the base");
        assertEqual(CavaRules.retryDelay(2, 2000, 60000), 4000, "retryDelay: doubled");
        assertEqual(CavaRules.retryDelay(5, 2000, 60000), 32000, "retryDelay: doubled at each failure");
        assertEqual(CavaRules.retryDelay(6, 2000, 60000), 60000, "retryDelay: at most the most");
        assertEqual(CavaRules.retryDelay(1000, 2000, 60000), 60000, "retryDelay: many failures, still the most");
        assertEqual(CavaRules.retryDelay(5000, 2000, 60000), 60000, "retryDelay: past what a number holds, still the most");
        assertEqual(CavaRules.retryDelay(undefined, 2000, 60000), 2000, "retryDelay: no count, the base");

        assertEqual(CavaRules.logLine("", ""), "", "logLine: fine and still fine, nothing");
        assertEqual(CavaRules.logLine("cava exited with code 127", "cava exited with code 127"), "", "logLine: the same failure again, nothing");
        assert(CavaRules.logLine("", "cava exited with code 127").includes("cava exited with code 127"), "logLine: a failure names its problem");
        assert(CavaRules.logLine("cava could not be started", "cava exited with code 127").includes("code 127"), "logLine: another failure is new");
        assertEqual(CavaRules.logLine("cava exited with code 127", ""), "cava runs again", "logLine: back to fine");
    }
}
