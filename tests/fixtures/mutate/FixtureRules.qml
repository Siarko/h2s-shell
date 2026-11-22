pragma Singleton
import Quickshell

// tests/mutate-selftest.sh's subject, copied into a scratch tree as
// singletons/MutateFixtureRules.qml: seven mutants, of each outcome against FixtureTest.qml
Singleton {
    // '<' -> '<=' and '>' -> '>=' cannot be loaded: not compiled
    property list<int> sizes
    function adult(age) {
        // Negated: killed. '>=' -> '>' and 18 -> 19: no check tells, they survive
        return age >= 18;
    }
    function minor(age) {
        // The '!' dropped, and negated: both killed
        return !adult(age);
    }
}
