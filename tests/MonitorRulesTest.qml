import QtQuick
import qs.singletons

// Which monitor is which (singletons/MonitorRules.qml): ids from make|model|serial, the
// fallback without a serial, twins told apart by their connector whatever their order and
// reported, the laptop's panel, Hyprland's answer read (power on/off/unknown, disabled
// outputs and mirrors left out, an unreadable answer), the dispatch and its answer, and the
// per-monitor override.
TestCase {
    suiteName: "MonitorRules"

    function run() {
        const rules = MonitorRules;
        const samsung = { connector: "DP-2", make: "Samsung Electric Company", model: "C27JG5x", serial: "H4ZMC00268" };
        const gigabyte = { connector: "HDMI-A-1", make: "GIGA-BYTE TECHNOLOGY CO., LTD.", model: "MO27Q28G", serial: "25452F000907" };
        const twinA = { connector: "DP-1", make: "Dell Inc.", model: "U2419H", serial: "" };
        const twinB = { connector: "DP-3", make: "Dell Inc.", model: "U2419H", serial: "" };

        // --- one monitor's id ---
        assertEqual(rules.identity(samsung), "Samsung Electric Company|C27JG5x|H4ZMC00268", "make|model|serial");
        assertEqual(rules.identity(twinA), "Dell Inc.|U2419H|", "without a serial: make|model|");
        assertEqual(rules.identity({ connector: "DP-1" }), "||", "nothing known: empty fields, still an id");
        assertEqual(rules.identity({ make: "A|B", model: "line\nbreak", serial: "  x  " }), "A B|line break|x",
                    "text from outside: no separator, on one line, trimmed");
        assertEqual(rules.identity({ make: "M".repeat(200), model: "", serial: "" }).length, 82, "… each field length-capped");
        assertEqual(rules.identity({ make: 7, model: null, serial: undefined }), "||", "… a field that is not text is empty");

        // --- several: twins ---
        let named = rules.identities([samsung, gigabyte]);
        assertEqual(named.ids["DP-2"], rules.identity(samsung), "different monitors keep their plain ids");
        assertEqual(named.ids["HDMI-A-1"], rules.identity(gigabyte), "… each");
        assertEqual(JSON.stringify(named.twins), "[]", "… no twins");

        named = rules.identities([twinA, samsung, twinB]);
        assertEqual(named.ids["DP-1"], "Dell Inc.|U2419H||DP-1", "twins: each id takes its connector");
        assertEqual(named.ids["DP-3"], "Dell Inc.|U2419H||DP-3", "… the other");
        assertEqual(named.ids["DP-2"], rules.identity(samsung), "… a third monitor keeps its plain id");
        assertEqual(JSON.stringify(named.twins), JSON.stringify(["Dell Inc.|U2419H|"]), "… the twins reported, once");
        const reversed = rules.identities([twinB, samsung, twinA]);
        assertEqual(JSON.stringify([reversed.ids["DP-1"], reversed.ids["DP-3"]]), JSON.stringify([named.ids["DP-1"], named.ids["DP-3"]]),
                    "… the same ids whatever order the monitors come in");

        const sameSerial = rules.identities([Object.assign({}, twinA, { serial: "0" }), Object.assign({}, twinB, { serial: "0" })]);
        assertEqual(sameSerial.ids["DP-1"], "Dell Inc.|U2419H|0|DP-1", "twins with one placeholder serial are told apart too");
        assertEqual(rules.identities([twinA]).ids["DP-1"], "Dell Inc.|U2419H|", "a twin alone again: its plain id");
        assertEqual(JSON.stringify(rules.identities(null)), JSON.stringify({ ids: {}, twins: [] }), "no monitors: nothing");

        // --- the laptop's panel ---
        assert(rules.isBuiltIn("eDP-1"), "eDP- is built in");
        assert(rules.isBuiltIn("LVDS-1") && rules.isBuiltIn("DSI-1"), "… LVDS- and DSI- too");
        assert(!rules.isBuiltIn("DP-1") && !rules.isBuiltIn("HDMI-A-1"), "… DP- and HDMI- are not");
        assert(!rules.isBuiltIn("") && !rules.isBuiltIn(null), "… nothing is not");

        // --- the backend ---
        assertEqual(rules.backend({ hyprland: true }), "hyprland", "under Hyprland: its dispatch");
        assertEqual(rules.backend({ hyprland: false }), "none", "elsewhere, for now: none");
        assertEqual(rules.backend(undefined), "none", "… nothing known: none");

        // --- power ---
        assertEqual(rules.power(true), "on", "dpmsStatus true: on");
        assertEqual(rules.power(false), "off", "… false: off");
        assertEqual(rules.power(undefined), "unknown", "… missing: unknown");
        assertEqual(rules.power("false"), "unknown", "… not a boolean: unknown, never off");

        // --- Hyprland's answer ---
        const answer = JSON.stringify([
            { name: "DP-2", make: samsung.make, model: samsung.model, serial: samsung.serial, dpmsStatus: false, disabled: false, mirrorOf: "none" },
            { name: "eDP-1", make: "BOE", model: "0x0BCA", serial: "", dpmsStatus: true, disabled: false, mirrorOf: "none" },
            { name: "HDMI-A-1", make: "X", model: "Y", serial: "Z", dpmsStatus: true, disabled: true, mirrorOf: "none" },
            { name: "DP-5", make: "X", model: "M", serial: "1", dpmsStatus: true, disabled: false, mirrorOf: "DP-2" },
            { name: "bad\" name", make: "X", model: "Q", serial: "2", dpmsStatus: true },
            { name: "DP-6", make: "X", model: "W", serial: "3" }
        ]);
        const read = rules.hyprlandMonitors(answer);
        assertEqual(read.monitors.map(monitor => monitor.connector + "=" + monitor.power).join(" "), "DP-2=off eDP-1=on DP-6=unknown",
                    "Hyprland's answer: each monitor's power; disabled, mirrors and unusable names left out");
        assertEqual(read.monitors[0].id, rules.identity(samsung), "… each with its id");
        assert(read.monitors[1].builtIn && !read.monitors[0].builtIn, "… and whether it is built in");
        assertEqual(JSON.stringify(read.twins), "[]", "… no twins");
        const twins = rules.hyprlandMonitors(JSON.stringify([
            { name: "DP-3", make: "Dell Inc.", model: "U2419H", serial: "", dpmsStatus: true },
            { name: "DP-1", make: "Dell Inc.", model: "U2419H", serial: "", dpmsStatus: true }
        ]));
        assertEqual(twins.monitors.map(monitor => monitor.id).join(" "), "Dell Inc.|U2419H||DP-3 Dell Inc.|U2419H||DP-1", "twins read: told apart");
        assertEqual(twins.twins.length, 1, "… and reported");
        assertEqual(rules.hyprlandMonitors("[]").monitors.length, 0, "no monitors: an empty list, read");
        assertEqual(rules.hyprlandMonitors("[{ \"name\": "), null, "not JSON: no answer");
        assertEqual(rules.hyprlandMonitors("{}"), null, "… not a list: no answer");
        assertEqual(rules.hyprlandMonitors(""), null, "… nothing: no answer");
        assertEqual(rules.unknownPower(read.monitors).map(monitor => monitor.power).join(" "), "unknown unknown unknown",
                    "after a failed reading: the monitors kept, every power unknown");
        assertEqual(read.monitors[0].power, "off", "… the reading itself unchanged");

        // --- the run's answer ---
        assertEqual(rules.readProblem({ ok: true, code: 0 }), "", "a reading that ran: no problem");
        assertEqual(rules.readProblem({ ok: false, failedToStart: true }), "hyprctl could not be started", "… not started");
        assertEqual(rules.readProblem({ ok: false, timedOut: true }), "hyprctl did not answer", "… timed out");
        assertEqual(rules.readProblem({ ok: true, truncated: true }), "too much output from hyprctl", "… cut short: not believed");
        assertEqual(rules.readProblem({ ok: false, code: 1, stderr: "no instance\nmore" }), "hyprctl failed (1): no instance", "… failed, its first line");
        assertEqual(rules.readProblem(null), "hyprctl gave no answer", "… no result");

        // --- the dispatch ---
        assertEqual(rules.hyprlandDpms("DP-2", false), "hl.dsp.dpms({ action = \"disable\", monitor = \"DP-2\" })", "off: disable, for that connector");
        assertEqual(rules.hyprlandDpms("HDMI-A-1", true), "hl.dsp.dpms({ action = \"enable\", monitor = \"HDMI-A-1\" })", "on: enable");
        assertEqual(rules.hyprlandDpms("", false), "", "no connector: no dispatch (Hyprland would turn every monitor off)");
        assertEqual(rules.hyprlandDpms("DP-2\" }) hl.exec(\"x", false), "", "… nor one that would break out of the expression");
        assertEqual(rules.hyprlandDpms(null, true), "", "… nor no name");
        assertEqual(rules.dispatchProblem({ ok: true, code: 0, stdout: "ok\n" }), "", "the dispatch answered ok: worked");
        assertEqual(rules.dispatchProblem({ ok: true, code: 0, stdout: "error: no such dispatcher" }), "hyprctl dispatch failed: error: no such dispatcher",
                    "… exit 0 with another answer: failed");
        assertEqual(rules.dispatchProblem({ ok: false, code: 3, stdout: "", stderr: "Couldn't connect" }), "hyprctl dispatch failed (3): Couldn't connect",
                    "… a failed run, its stderr");
        assertEqual(rules.dispatchProblem({ ok: false, failedToStart: true }), "hyprctl could not be started", "… not started");
        assertEqual(rules.dispatchProblem({ ok: false, timedOut: true }), "hyprctl did not answer", "… timed out");

        // --- the per-monitor override ---
        const overrides = { [rules.identity(samsung)]: "off", "Dell Inc.|U2419H||DP-1": "screensaver" };
        assertEqual(rules.overrideFor(overrides, rules.identity(samsung)), "off", "a monitor's override, by its id");
        assertEqual(rules.overrideFor(overrides, rules.identity(gigabyte)), "", "… none for a monitor without one");
        assertEqual(rules.overrideFor(null, "x"), "", "… none in no map");
        assertEqual(rules.overrideFor(["off"], "0"), "", "… none in a list");
        assertEqual(rules.overrideFor({ x: 3 }, "x"), "", "… a way that is not text is none");
        assertEqual(JSON.stringify(rules.notConnected(overrides, [rules.identity(samsung)])), JSON.stringify(["Dell Inc.|U2419H||DP-1"]),
                    "overrides of monitors not connected, to be listed");
        assertEqual(JSON.stringify(rules.notConnected(overrides, [])), JSON.stringify(Object.keys(overrides).sort()), "… all, sorted, when none is");
        assertEqual(JSON.stringify(rules.notConnected(undefined, [])), "[]", "… none without a map");
    }
}
