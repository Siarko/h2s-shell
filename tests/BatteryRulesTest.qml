import QtQuick
import qs.singletons

TestCase {
    suiteName: "BatteryRules"

    function _code(text) {
        return text.codePointAt(0).toString(16);
    }

    function run() {
        // --- the charge in tens ---
        assertEqual(BatteryRules.step(0), 0, "empty");
        assertEqual(BatteryRules.step(4), 0, "under 5 % shows empty");
        assertEqual(BatteryRules.step(5), 10, "5 % rounds up to a tenth");
        assertEqual(BatteryRules.step(64), 60, "64 % is the 60 icon");
        assertEqual(BatteryRules.step(96), 100, "96 % is full");
        assertEqual(BatteryRules.step(130), 100, "never past full");
        assertEqual(BatteryRules.step(-3), 0, "never under empty");

        // --- icons ---
        assertEqual(_code(BatteryRules.icon(true, 60, false)), "f007f", "60 %, discharging: md-battery_60");
        assertEqual(_code(BatteryRules.icon(true, 100, false)), "f0079", "full: md-battery");
        assertEqual(_code(BatteryRules.icon(true, 2, false)), "f008e", "empty: the outline");
        assertEqual(_code(BatteryRules.icon(true, 60, true)), "f0089", "60 %, charging: md-battery_charging_60");
        assertEqual(_code(BatteryRules.icon(true, 50, true)), "f089d", "50 %, charging: md-battery_charging_50");
        assertEqual(_code(BatteryRules.icon(true, 100, true)), "f0085", "full, charging: md-battery_charging_100");
        assertEqual(_code(BatteryRules.icon(false, 60, false)), "f125e", "no battery: md-battery_off_outline");
        for (let percent = 0; percent <= 100; percent += 10) {
            assert(BatteryRules.icon(true, percent, false).length > 0 && BatteryRules.icon(true, percent, true).length > 0,
                   "an icon for " + percent + " %, charging or not");
        }

        // --- hex colours ---
        assert(BatteryRules.isHexColor("#e05252"), "#rrggbb");
        assert(BatteryRules.isHexColor("#80E05252"), "#aarrggbb, either case");
        assert(!BatteryRules.isHexColor("e05252"), "no #");
        assert(!BatteryRules.isHexColor("#e0525"), "too short");
        assert(!BatteryRules.isHexColor("red"), "a name is not hex");

        // --- colour from thresholds ---
        const fallback = "#ffffff";
        const thresholds = [{ value: 30, color: "#e0a052" }, { value: 15, color: "#e05252" }];
        assertEqual(String(BatteryRules.color(10, thresholds, fallback)), "#e05252", "10 %: the tightest threshold, 15");
        assertEqual(String(BatteryRules.color(15, thresholds, fallback)), "#e05252", "at the threshold counts");
        assertEqual(String(BatteryRules.color(25, thresholds, fallback)), "#e0a052", "25 %: under 30 only");
        assertEqual(String(BatteryRules.color(50, thresholds, fallback)), fallback, "50 %: over every threshold, the fallback");
        assertEqual(String(BatteryRules.color(50, [], fallback)), fallback, "no thresholds: the fallback");
        assertEqual(String(BatteryRules.color(50, undefined, fallback)), fallback, "thresholds missing: the fallback");
        assertEqual(String(BatteryRules.color(10, [{ value: 20, color: "nope" }, { value: 40, color: "#00ff00" }], fallback)),
                    "#00ff00", "a threshold with an invalid colour is left out");
        assertEqual(String(BatteryRules.color(10, [{ value: "", color: "#ff0000" }], fallback)), fallback,
                    "a threshold with no number is left out");
        assertEqual(String(BatteryRules.color(100, [{ value: 100, color: "#00ff00" }], fallback)), "#00ff00",
                    "a threshold at 100 colours a full battery");
    }
}
