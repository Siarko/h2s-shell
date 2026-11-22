// Copied into a scratch tree as tests/MutateFailingTest.qml (tests/mutate-selftest.sh): fails
// unmutated, so no mutant can be judged
TestCase {
    suiteName: "MutateFailing"

    function run() {
        assert(false, "fails as it is");
    }
}
