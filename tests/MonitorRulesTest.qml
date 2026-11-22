import QtQuick
import qs.singletons

// Which monitor is which (singletons/MonitorRules.qml): ids from make|model|serial, the
// fallback without a serial, twins told apart by their connector whatever their order and
// reported, the laptop's panel, Hyprland's answer read (power on/off/unknown, disabled
// outputs and mirrors left out, an unreadable answer), wlopm's answer and command, the
// backend chosen, the dispatch and its answer, and the
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
        assertEqual(rules.backend({ hyprland: false }), "none", "elsewhere, without wlopm: none");
        assertEqual(rules.backend({ hyprland: false, wlopm: true }), "wlopm", "elsewhere, wlopm found: wlopm");
        assertEqual(rules.backend({ hyprland: true, wlopm: true }), "hyprland", "… under Hyprland, Hyprland's own first");
        assertEqual(rules.backend({ wlopm: "yes" }), "none", "… wlopm not known to be found: none");
        assertEqual(rules.backend(undefined), "none", "… nothing known: none");
        assertEqual(JSON.stringify(rules.unavailable("none")), JSON.stringify({ reason: "Not supported here", hint: "Install wlopm to turn monitors off" }),
                    "no backend: the page's reason, and the hint names wlopm");
        assertEqual(rules.unavailable("wlopm").reason + rules.unavailable("hyprland").hint, "", "… a backend: nothing to say");

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
        assertEqual(rules.hyprlandMonitors("[{\"name\": \"constructor\", \"dpmsStatus\": true}]").monitors.length, 1, "… a connector named like an object key: read");
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

        // --- wlopm's answer ---
        const screens = [{ name: "DP-2", model: "C27JG5x", serialNumber: "" }, { name: "eDP-1", model: "0x0BCA", serialNumber: "S1" },
                         { name: "DP-1", model: "U2419H", serialNumber: "" }, { name: "DP-3", model: "U2419H", serialNumber: "" }, null, { name: 7 }];
        const wlopm = rules.wlopmMonitors(JSON.stringify([
            { output: "DP-2", "power-mode": "off" },
            { output: "eDP-1", "power-mode": "on" },
            { output: "HDMI-A-1", error: "failed" },
            { output: "DP-4", "power-mode": "standby" },
            { output: "*", "power-mode": "on" },
            { output: "-x", "power-mode": "on" },
            { output: "DP-2", "power-mode": "on" },
            "DP-7",
            null
        ]), screens);
        assertEqual(wlopm.monitors.map(monitor => monitor.connector + "=" + monitor.power).join(" "), "DP-2=off eDP-1=on HDMI-A-1=unknown DP-4=unknown",
                    "wlopm's answer: each output's power; an error or a mode it does not name: unknown; `*`, unusable names and repeats left out");
        assertEqual(wlopm.monitors.map(monitor => monitor.id).join(" "), "|C27JG5x| |0x0BCA|S1 |||HDMI-A-1 |||DP-4",
                    "… ids from the screen of that name (no make from Qt); outputs Qt does not know: empty fields, twins by connector");
        assertEqual(JSON.stringify(wlopm.twins), JSON.stringify(["||"]), "… reported as twins");
        assert(wlopm.monitors[1].builtIn && !wlopm.monitors[0].builtIn, "… the laptop's panel recognised");
        const wlopmTwins = rules.wlopmMonitors("[{\"output\": \"DP-3\", \"power-mode\": \"on\"}, {\"output\": \"DP-1\", \"power-mode\": \"on\"}]", screens);
        assertEqual(wlopmTwins.monitors.map(monitor => monitor.id).join(" "), "|U2419H||DP-3 |U2419H||DP-1", "two of one model without a serial: told apart by connector");
        assertEqual(rules.wlopmMonitors("[{\"output\": \"DP-1\", \"power-mode\": \"on\"}]", screens, ["|U2419H|"]).monitors[0].id, "|U2419H||DP-1",
                    "… a twin left alone keeps its id");
        assertEqual(rules.wlopmMonitors("[{\"output\": \"constructor\", \"power-mode\": \"on\"}]", [{ name: "constructor", model: "M" }]).monitors[0].id, "|M|",
                    "… a connector that is an object key is looked up as a name only");
        assertEqual(rules.wlopmMonitors("[{\"output\": \"DP-2\", \"power-mode\": \"on\"}]", [{ name: "DP-2", manufacturer: samsung.make, model: samsung.model, serialNumber: "" }]).monitors[0].id,
                    samsung.make + "|" + samsung.model + "|", "… the make from Qt's screen too");
        assertEqual(rules.wlopmMonitors("[]", screens).monitors.length, 0, "no outputs: an empty list, read");
        assertEqual(rules.wlopmMonitors("[{ \"output\": ", screens), null, "not JSON: no answer");
        assertEqual(rules.wlopmMonitors("{}", screens), null, "… not a list: no answer");
        assertEqual(rules.wlopmMonitors(undefined, screens), null, "… nothing: no answer");
        assertEqual(rules.wlopmMonitors("[{\"output\": \"DP-2\", \"power-mode\": \"on\"}]", null).monitors[0].id, "||", "… no screens known: empty fields, still read");
        assertEqual(rules.wlopmPower("on") + " " + rules.wlopmPower("off") + " " + rules.wlopmPower(undefined) + " " + rules.wlopmPower(true), "on off unknown unknown",
                    "power-mode: on, off, else unknown, never off");

        // --- the wlopm command ---
        assertEqual(JSON.stringify(rules.wlopmCommand("wlopm", "DP-2", false)), JSON.stringify(["wlopm", "--off", "DP-2"]), "off: --off, that connector, argv");
        assertEqual(JSON.stringify(rules.wlopmCommand("/x/wlopm", "HDMI-A-1", true)), JSON.stringify(["/x/wlopm", "--on", "HDMI-A-1"]), "on: --on");
        assertEqual(JSON.stringify(rules.wlopmCommand("wlopm", "*", false)), "[]", "`*` (every output): no command");
        assertEqual(JSON.stringify(rules.wlopmCommand("wlopm", "", false)), "[]", "… no connector: none");
        assertEqual(JSON.stringify(rules.wlopmCommand("wlopm", "--json", false)), "[]", "… a name that reads as an option: none");
        assertEqual(JSON.stringify(rules.wlopmCommand("wlopm", "DP-2; rm x", false)), "[]", "… a name with spaces or other characters: none");
        assertEqual(JSON.stringify(rules.wlopmCommand("", "DP-2", false)), "[]", "… no program: none");

        // --- the run's answer ---
        assertEqual(rules.readProblem({ ok: true, code: 0 }), "", "a reading that ran: no problem");
        assertEqual(rules.readProblem({ ok: false, failedToStart: true }), "hyprctl could not be started", "… not started");
        assertEqual(rules.readProblem({ ok: false, timedOut: true }), "hyprctl did not answer", "… timed out");
        assertEqual(rules.readProblem({ ok: true, truncated: true }), "too much output from hyprctl", "… cut short: not believed");
        assertEqual(rules.readProblem({ ok: false, code: 1, stderr: "no instance\nmore" }), "hyprctl failed (1): no instance", "… failed, its first line");
        assertEqual(rules.readProblem(null), "hyprctl gave no answer", "… no result");
        assertEqual(rules.readProblem({ ok: false, code: 1, stderr: "ERROR: no protocol" }, "wlopm"), "wlopm failed (1): ERROR: no protocol", "… wlopm's, by its name");
        assertEqual(rules.readProblem({ ok: false, failedToStart: true }, "wlopm"), "wlopm could not be started", "… wlopm not started");

        // --- the dispatch ---
        assertEqual(rules.hyprlandDpms("DP-2", false), "hl.dsp.dpms({ action = \"disable\", monitor = \"DP-2\" })", "off: disable, for that connector");
        assertEqual(rules.hyprlandDpms("HDMI-A-1", true), "hl.dsp.dpms({ action = \"enable\", monitor = \"HDMI-A-1\" })", "on: enable");
        assertEqual(rules.hyprlandDpms("", false), "", "no connector: no dispatch (Hyprland would turn every monitor off)");
        assertEqual(rules.hyprlandDpms("DP-2\" }) hl.exec(\"x", false), "", "… nor one that would break out of the expression");
        assertEqual(rules.hyprlandDpms(null, true), "", "… nor no name");
        assertEqual(rules.dispatchProblem({ ok: true, code: 0, stdout: "ok\n" }), "", "the dispatch ran: no problem of the run");
        assertEqual(rules.dispatchProblem({ ok: true, code: 0, stdout: "error: no such dispatcher" }), "",
                    "… whatever it printed: whether the monitor changed is the next reading's");
        assertEqual(rules.dispatchProblem({ ok: false, code: 3, stdout: "", stderr: "Couldn't connect" }), "hyprctl dispatch failed (3): Couldn't connect",
                    "… a failed run, its stderr");
        assertEqual(rules.dispatchProblem({ ok: false, failedToStart: true }), "hyprctl could not be started", "… not started");
        assertEqual(rules.dispatchProblem({ ok: false, timedOut: true }), "hyprctl did not answer", "… timed out");
        assertEqual(rules.dispatchProblem({ ok: false, code: 1, stdout: "", stderr: "ERROR: Output 'X' does not exist." }, "wlopm"),
                    "wlopm failed (1): ERROR: Output 'X' does not exist.", "… wlopm's, by its name");
        assertEqual(rules.dispatchProblem({ ok: false, timedOut: true }, "wlopm"), "wlopm did not answer", "… wlopm timed out");

        // --- the action, by the reading after it ---
        const after = [{ id: "a", connector: "DP-1", power: "off" }, { id: "b", connector: "DP-2", power: "on" }, { id: "c", connector: "DP-3", power: "unknown" }];
        assertEqual(rules.actionProblem(after, "a", false), "", "off asked, read off: worked");
        assertEqual(rules.actionProblem(after, "b", false), "it is still on", "off asked, read on: a problem, even after \"ok\"");
        assertEqual(rules.actionProblem(after, "a", true), "it is still off", "on asked, read off: a problem");
        assertEqual(rules.actionProblem(after, "c", false), "its power could not be read", "… read unknown: a problem");
        assertEqual(rules.actionProblem(after, "z", false), "the monitor is gone", "… gone: a problem");
        assertEqual(rules.actionProblem(null, "a", false), "the monitors could not be read after it", "… no reading: a problem");

        // --- monitors turned off by another's action ---
        const before = [{ connector: "DP-1", power: "on" }, { connector: "DP-2", power: "on" }, { connector: "DP-3", power: "off" }, { connector: "DP-4", power: "on" }];
        const allOff = [{ connector: "DP-1", power: "off" }, { connector: "DP-2", power: "off" }, { connector: "DP-3", power: "off" }, { connector: "DP-4", power: "unknown" }];
        assertEqual(JSON.stringify(rules.turnedOffBesides(before, allOff, "DP-1")), JSON.stringify(["DP-2"]),
                    "on before, off after, not the target: turned back on; off before or unknown after: left");
        assertEqual(JSON.stringify(rules.turnedOffBesides(before, [{ connector: "DP-9", power: "off" }], "DP-1")), "[]", "… a monitor not there before: left");
        assertEqual(JSON.stringify(rules.turnedOffBesides(before, null, "DP-1")), "[]", "… no reading after: nothing");

        // --- a twin left alone keeps its id ---
        assertEqual(rules.identities([twinA], ["Dell Inc.|U2419H|"]).ids["DP-1"], "Dell Inc.|U2419H||DP-1", "an identity seen as twins: the connector kept");
        assertEqual(JSON.stringify(rules.identities([twinA], ["Dell Inc.|U2419H|"]).twins), JSON.stringify(["Dell Inc.|U2419H|"]), "… still reported");
        const alone = rules.hyprlandMonitors(JSON.stringify([{ name: "DP-1", make: "Dell Inc.", model: "U2419H", serial: "", dpmsStatus: true }]), ["Dell Inc.|U2419H|"]);
        assertEqual(alone.monitors[0].id, "Dell Inc.|U2419H||DP-1", "… in Hyprland's answer too");
        assertEqual(alone.monitors[0].base, "Dell Inc.|U2419H|", "… with its identity before twins as `base`");

        // --- the per-monitor override ---
        const overrides = { [rules.identity(samsung)]: "off", "Dell Inc.|U2419H||DP-1": "screensaver" };
        assertEqual(rules.overrideFor(overrides, rules.identity(samsung)), "off", "a monitor's override, by its id");
        assertEqual(rules.overrideFor(overrides, rules.identity(gigabyte)), "", "… none for a monitor without one");
        assertEqual(rules.overrideFor(null, "x"), "", "… none in no map");
        assertEqual(rules.overrideFor(["off"], "0"), "", "… none in a list");
        assertEqual(rules.overrideFor({ x: 3 }, "x"), "", "… a way that is not text is none");
        assertEqual(JSON.stringify(rules.overrideFor({ x: { screenOffEnabled: true } }, "x")), JSON.stringify({ screenOffEnabled: true }),
                    "… an entry that is an object (a monitor's times): found");
        assertEqual(rules.overrideFor({ x: [1] }, "x"), "", "… a list is no entry");

        // No backend reads the monitors: the screens Qt knows, with ids made the same way
        const fromScreens = rules.screenMonitors([
            { name: "DP-1", manufacturer: "Samsung", model: "Odyssey", serialNumber: "S1" },
            { name: "DP-2", manufacturer: "Dell", model: "U2419H", serialNumber: "" },
            { name: "DP-3", manufacturer: "Dell", model: "U2419H" },
            { name: "DP-1", manufacturer: "Other", model: "X", serialNumber: "2" },
            { name: "", manufacturer: "Nameless" }, null, "DP-9",
            { name: "eDP-1", manufacturer: "a|b", model: "c\nd", serialNumber: 7 }
        ], []);
        assertEqual(JSON.stringify(fromScreens), JSON.stringify([
            { id: "Samsung|Odyssey|S1", base: "Samsung|Odyssey|S1", connector: "DP-1" },
            { id: "Dell|U2419H||DP-2", base: "Dell|U2419H|", connector: "DP-2" },
            { id: "Dell|U2419H||DP-3", base: "Dell|U2419H|", connector: "DP-3" },
            { id: "a b|c d|", base: "a b|c d|", connector: "eDP-1" }
        ]), "the screens: make|model|serial ids, twins by their connector, one per name, fields made safe");
        assertEqual(JSON.stringify(rules.screenMonitors([{ name: "DP-2", manufacturer: "Dell", model: "U2419H" }], ["Dell|U2419H|"])),
                    JSON.stringify([{ id: "Dell|U2419H||DP-2", base: "Dell|U2419H|", connector: "DP-2" }]), "… a twin seen before keeps its connector");
        assertEqual(JSON.stringify(rules.screenMonitors(undefined, [])), "[]", "… no screens: none");
        assertEqual(rules.looseKey({ "A|M|S|DP-1": {}, "A|M|": {} }, { id: "A|M|S", base: "A|M|S", connector: "DP-1" }), "",
                    "an exact key holding an object: nothing taken loosely");
        assertEqual(JSON.stringify(rules.notConnected(overrides, [rules.identity(samsung)])), JSON.stringify(["Dell Inc.|U2419H||DP-1"]),
                    "overrides of monitors not connected, to be listed");
        assertEqual(JSON.stringify(rules.notConnected(overrides, [])), JSON.stringify(Object.keys(overrides).sort()), "… all, sorted, when none is");
        assertEqual(JSON.stringify(rules.notConnected(undefined, [])), "[]", "… none without a map");

        // A twin's override under either form: set while it was a twin, or before
        const twinNow = { id: "Dell Inc.|U2419H||DP-1", base: "Dell Inc.|U2419H|", connector: "DP-1" };
        const plainNow = { id: "Dell Inc.|U2419H|", base: "Dell Inc.|U2419H|", connector: "DP-1" };
        assertEqual(rules.overrideFor({ "Dell Inc.|U2419H|": "off" }, twinNow), "off", "a twin: its plain identity's override, set before it had a twin");
        assertEqual(rules.overrideFor({ "Dell Inc.|U2419H||DP-1": "off" }, plainNow), "off", "a monitor alone: the override set while it was a twin, on this connector");
        assertEqual(rules.overrideFor({ "Dell Inc.|U2419H||DP-3": "off" }, plainNow), "", "… not one of another connector");
        assertEqual(rules.overrideFor({ "Dell Inc.|U2419H||DP-1": "screensaver", "Dell Inc.|U2419H|": "off" }, twinNow), "screensaver", "… its own id first");
        assertEqual(JSON.stringify(rules.notConnected({ "Dell Inc.|U2419H|": "off", "Gone|X|1": "off" }, [twinNow])), JSON.stringify(["Gone|X|1"]),
                    "an override a connected twin uses under its plain identity: not listed as not connected");
        assertEqual(JSON.stringify(rules.notConnected({ "Dell Inc.|U2419H||DP-1": "off" }, [plainNow])), "[]", "… nor one it uses under its twin form");

        // A field one backend does not report: matched loosely, when only one key fits
        const hyprlandKey = rules.identity(samsung);
        const fromWlopm = { id: "Samsung Electric Company|C27JG5x|", base: "Samsung Electric Company|C27JG5x|", connector: "DP-2" };
        const fromWlopmNoMake = { id: "|C27JG5x|", base: "|C27JG5x|", connector: "DP-2" };
        assertEqual(rules.overrideFor({ [hyprlandKey]: "off" }, fromWlopm), "off", "set on Hyprland, read without a serial: its override");
        assertEqual(rules.overrideFor({ [hyprlandKey]: "off" }, fromWlopmNoMake), "off", "… read without make and serial too");
        assertEqual(JSON.stringify(rules.notConnected({ [hyprlandKey]: "off" }, [fromWlopm])), "[]", "… and not listed as not connected");
        const fromHyprland = { id: hyprlandKey, base: hyprlandKey, connector: "DP-2" };
        assertEqual(rules.overrideFor({ "Samsung Electric Company|C27JG5x|": "off" }, fromHyprland), "off", "set without a serial, read on Hyprland with one: its override");
        assertEqual(JSON.stringify(rules.notConnected({ "|C27JG5x|": "off" }, [fromHyprland])), "[]", "… set with no make either: not listed as not connected");
        assertEqual(rules.overrideFor({ [hyprlandKey]: "off", "Samsung Electric Company|C27JG5x|OTHER": "screensaver" }, fromWlopm), "",
                    "two stored keys fit loosely: neither taken");
        assertEqual(rules.overrideFor({ [hyprlandKey]: "off", "Samsung Electric Company|C27JG5x|": "screensaver" }, fromWlopm), "screensaver", "an exact key first");
        assertEqual(rules.overrideFor({ "Samsung Electric Company|C27JG5x|OTHER": "off" }, fromHyprland), "", "a field both report, different: no match");
        assertEqual(rules.overrideFor({ "Samsung Electric Company||H4ZMC00268": "off" }, fromWlopm), "", "… no model on either side: no match");
        assertEqual(rules.overrideFor({ "Dell Inc.|U2419H|SER": "off" }, twinNow), "", "a twin: never loosely");
        assertEqual(rules.overrideFor({ "Dell Inc.|U2419H||DP-1": "off" }, { id: "|U2419H|", base: "|U2419H|", connector: "DP-3" }), "", "… nor a twin's stored key");
        assertEqual(rules.looseKey({ [hyprlandKey]: "off" }, "Samsung Electric Company|C27JG5x|"), hyprlandKey, "an id given as text: matched too");
        assertEqual(JSON.stringify(rules.notConnected({ [hyprlandKey]: "off", "Samsung Electric Company|C27JG5x|X": "off" }, [fromWlopm]).length), "2",
                    "two keys fit loosely: both listed, neither taken");

        // Another connected monitor's exact key is never taken loosely
        const dellA = { id: "Dell|U2419H|S1", base: "Dell|U2419H|S1", connector: "DP-1" };
        const dellB = { id: "Dell|U2419H|", base: "Dell|U2419H|", connector: "DP-3" };
        const onlyA = { "Dell|U2419H|S1": "off" };
        assertEqual(rules.overrideFor(onlyA, dellB, [dellA, dellB]), "", "A and B connected, only A stored: B gets nothing");
        assertEqual(rules.overrideFor(onlyA, dellA, [dellA, dellB]), "off", "… A its own");
        assertEqual(rules.overrideFor(onlyA, dellB, [dellB]), "off", "… B alone: A's key loosely");
        assertEqual(JSON.stringify(rules.notConnected(onlyA, [dellB, dellA])), "[]", "… A's key used by A: not listed");
        assertEqual(rules.connectedFor("Dell|U2419H|S1", [dellB, dellA]), dellA, "an id given: the monitor it names exactly, though another fits loosely first");
        assertEqual(rules.connectedFor("Dell|U2419H|S1", [dellB]), dellB, "… loosely when none names it exactly");
        assertEqual(rules.connectedFor("Gone|X|1", [dellB, dellA]), null, "… none: null");
    }
}
