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
        assert(GoodState.mainSawHandle, "the main had its handle, active, in its Component.onCompleted");
        assertEqual(GoodState.registrations.length, 1, "the main's registration is in");
        assert(GoodState.ticking, "the singleton's timer runs while the module is active");
    }
}
