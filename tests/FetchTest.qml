import QtQuick
import qs.singletons.network

TestCase {
    suiteName: "Fetch"

    function run() {
        // Test 1: placeholders are replaced in order
        assertEqual(Fetch._printf("/calendars/{0}/events/{1}", ["primary", "abc"]),
            "/calendars/primary/events/abc", "_printf replaces every placeholder");

        // Test 2: a placeholder may repeat
        assertEqual(Fetch._printf("{0}-{0}", ["x"]), "x-x", "_printf replaces a repeated placeholder");

        // Test 3: a missing argument leaves its placeholder visible instead of "undefined"
        assertEqual(Fetch._printf("/calendars/{0}/events/{1}", ["primary"]),
            "/calendars/primary/events/{1}", "_printf keeps the placeholder of a missing argument");

        // Test 4: falsy but present arguments are still substituted
        assertEqual(Fetch._printf("{0}/{1}", [0, ""]), "0/", "_printf substitutes falsy arguments");

        // Test 5: no placeholders, no change
        assertEqual(Fetch._printf("/colors", []), "/colors", "_printf leaves a plain URL alone");
    }
}
