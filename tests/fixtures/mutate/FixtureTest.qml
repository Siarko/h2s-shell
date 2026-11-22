import qs.singletons

// Copied into a scratch tree as tests/MutateFixtureRulesTest.qml (tests/mutate-selftest.sh)
TestCase {
    suiteName: "MutateFixtureRules"

    function run() {
        assert(MutateFixtureRules.adult(30), "30 is adult");
        assert(!MutateFixtureRules.adult(10), "10 is not");
        assert(MutateFixtureRules.minor(10), "10 is a minor");
    }
}
