import QtQuick
import qs.tests
import ".."

// The fixture module's own suite (tests/run-modules.sh): it extends the shell's TestCase and
// reaches the module's singleton — the instance the host's main uses
TestCase {
    suiteName: "good: GoodState"

    function run() {
        assertEqual(GoodState.greet("world"), "hello, world", "a pure function of the module");
        assertEqual(GoodState.mains, 1, "the host created the module's main, and this is the same singleton");
    }
}
