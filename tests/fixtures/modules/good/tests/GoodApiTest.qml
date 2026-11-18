import QtQuick
import qs.api
import qs.tests
import ".."

// The module API from a module's side (tests/run-modules.sh): only qs.api (and the shell's
// TestCase) — its handle, its settings, facts, store, the theme, the slot table, commands
// through the API's helpers against stand-in programs (tests/stand-in.sh, and its pkexec in
// tests/programs — the manifest's testPrograms), and module test mode as a module's suites see
// it (Api.testMode, its stand-ins, what openUrl and notify record: ModuleTestKit)
TestCase {
    id: suite
    suiteName: "good: the module API"
    asynchronous: true

    readonly property var module: Api.moduleAt(Qt.resolvedUrl("."))
    property var _steps: []

    function _then(description, condition, action) {
        _steps.push({ description: description, condition: condition, action: action });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite.finish();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {}
            if (!ready && waited < 8000)
                return;
            waited = 0;
            suite._steps.shift();
            if (!ready)
                suite.fail("timed out waiting: " + step.description);
            try {
                step.action();
            } catch (error) {
                suite.fail("threw in \"" + step.description + "\": " + error);
            }
        }
    }

    property CommandAction action: CommandAction {}
    property PrivilegedAction admin: PrivilegedAction {
        notifyFailures: false
    }
    property PrivilegedAction outsider: PrivilegedAction {
        notifyFailures: false
    }
    property CommandQuery query: CommandQuery {
        onDone: lines => suite._queried = lines
    }
    property var _queried: null
    property CommandRunner runner: CommandRunner {}
    property var _ran: null
    property var _ranLines: []
    property var _results: ({})

    // The store is read by a process (API 1.2): everything starts once it has answered
    function runAsync() {
        _then("the store is read", () => module?.store?.ready === true, () => _run());
        _clock.start();
    }

    function _run() {
        const standIn = module.directory + "/tests/stand-in.sh";
        // --- the handle ---
        assert(module !== null, "Api.moduleAt(Qt.resolvedUrl(\".\")) finds the module's handle from any of its files");
        assert(module === Api.module("good"), "… the same object as Api.module(id)");
        assertEqual(module?.moduleId + " " + module?.version + " " + module?.name, "good 1.2.3 Good fixture", "id, version, name");
        assert(module.active, "active while loaded");
        assertEqual(module.url("tests/x.qml"), "file://" + module.directory + "/tests/x.qml", "url(): a file of the module");
        assertEqual(module.manifest.widgets[0].type, "good", "its manifest, as read");
        try {
            module.manifest.id = "evil";
        } catch (error) {}
        assertEqual(module.manifest.id, "good", "… frozen: writing does nothing");
        assertEqual(Api.moduleAt("file:///etc/passwd"), null, "a file of no module: no handle");
        assertEqual(Api.module("no-such-module"), null, "an unknown id: no handle");

        // --- API version and slot table ---
        assertEqual(Api.version, "1.11", "Api.version");

        // --- module test mode (API 1.10): tests/run-modules.sh runs its suites in it ---
        assert(Api.testMode === true && ModuleTestKit.testMode, "Api.testMode: true under the module test runner");
        try {
            Api.testMode = false;
        } catch (error) {}
        assert(Api.testMode, "… read-only");
        // A module cannot switch it: not through what its handle reaches either
        try {
            module.host.testMode = false;
        } catch (error) {}
        assertEqual(module.host.setTestMode(false), false, "… setTestMode from a module: refused");
        assert(Api.testMode && module.host.testMode, "… still on");
        assertEqual(ModuleTestKit.status("good")?.deprecations.length, 0, "a 1.10 module: no test-mode gate in its deprecations");
        // Its programs (API 1.9): pkexec, from its testPrograms in test mode, never from PATH
        assertEqual(JSON.stringify(module.programs),
                    JSON.stringify({ pkexec: { path: module.directory + "/tests/programs/pkexec", trusted: true, reason: "test stand-in" } }),
                    "programs: pkexec is the stand-in in its testPrograms, trusted as one");
        assert(module.programsReady && Object.isFrozen(module.programs), "… ready, frozen");
        assertEqual(ModuleTestKit.status("good")?.state, "loaded", "ModuleTestKit.status(id)");
        assertEqual(ModuleTestKit.status("no-such-module"), null, "… null for no module");
        assert(ModuleTestKit.widgetEntries.some(entry => entry.module === "good" && entry.type === "good"), "ModuleTestKit.widgetEntries: its widget");
        // Links and notifications: recorded, nothing opened or sent
        ModuleTestKit.clearRecords();
        assert(Api.openUrl("https://example.org/a b"), "openUrl in test mode: true");
        assert(!Api.openUrl("javascript:alert(1)"), "… a link it refuses is still refused");
        assert(Api.openUrl("file:///tmp", { allowFile: true }), "… a file: link when allowed");
        assertEqual(JSON.stringify(ModuleTestKit.opened),
                    JSON.stringify([{ url: "https://example.org/a b", allowFile: false }, { url: "file:///tmp", allowFile: true }]),
                    "ModuleTestKit.opened: what would have been opened, in order");
        Api.notify("From the API", { body: "a body", urgency: "low" });
        module.notify("From the handle", { actions: [{ id: "go", label: "Go", onTriggered: () => suite.fail("a recorded notification's action ran") }] });
        const notified = ModuleTestKit.notified;
        assertEqual(notified.map(entry => entry.summary + "|" + entry.body + "|" + entry.appName + "|" + entry.urgency).join(","),
                    "From the API|a body|H2S Shell|low,From the handle||Good fixture|", "ModuleTestKit.notified: both, with the module's name on the handle's");
        assertEqual(JSON.stringify(notified[1]?.actions), "[\"Go\"]", "… its actions' labels");
        assertEqual(notified[0]?.command?.[0], "notify-send", "… and the words notify-send would have had");
        ModuleTestKit.clearRecords();
        assertEqual(ModuleTestKit.opened.length + ModuleTestKit.notified.length, 0, "clearRecords()");

        // --- its widget's presets (API 1.3) ---
        assertEqual(module.presetValue("good", "", "label"), "G", "presetValue: no preset, the manifest's presetDefaults");
        assertEqual(module.presetValue("clock", "", "format"), undefined, "… the core's types: nothing");
        assert(module.setPresetValue("clock", "Clock", "format", "x") !== "", "setPresetValue: refused for a type not its own");
        assert(module.setPresetValue("good", "", "label", "x") !== "", "… refused without a preset");
        assert(module.setPresetValue("good", "No such preset", "label", "x") !== "", "… refused for a preset that does not exist (it never creates one)");
        assertEqual(module.presetValue("good", "No such preset", "label"), "G", "… nothing written: still the default");
        assert(module.setPresetValue("good", "__proto__", "label", "x") !== "", "… refused for the name __proto__");
        // Writing to a preset the section editor made: tests/ModuleRegistriesTest.qml
        assert(Api.slots.some(slot => slot.name === "network.popup.sections"), "the slot table names the slots offered");

        // --- the theme, read-only ---
        assert(String(Api.theme.accent).startsWith("#"), "a colour token");
        assert(Api.theme.fontFamily !== "" && Api.theme.fontSizeBody > 0, "font family and sizes");
        assert(Api.theme.duration("enter") > 0, "durations");
        let threw = false;
        try {
            Api.theme.fontSizeBody = 99;
        } catch (error) {
            threw = true;
        }
        assert(threw || Api.theme.fontSizeBody !== 99, "a token cannot be written");
        const radius = Api.theme.row.radius;
        try {
            Api.theme.row.radius = 1234;
        } catch (error) {}
        assertEqual(Api.theme.row.radius, radius, "a group is a frozen copy");
        // Deep: nothing nested is the core's own object (API 1.2)
        const nestedOpen = group => Object.keys(group).some(key => {
            const value = group[key];
            return value !== null && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype
                && (!Object.isFrozen(value) || nestedOpen(value));
        });
        for (const name of ["capsule", "popup", "row", "settings", "border"])
            assert(Object.isFrozen(Api.theme[name]) && !nestedOpen(Api.theme[name]), "theme." + name + ": frozen all the way down");
        const easing = Api.theme.curve("enter");
        assert(easing === null || typeof easing !== "object" || Object.isFrozen(easing), "curve(): a frozen copy");

        // --- settings: its own only ---
        assertEqual(module.value("greeting"), "hello", "value(name): its setting's default");
        assertEqual(module.value("mod.good.greeting"), "hello", "value(full key)");
        assertEqual(module.value("mod.key-collision.fine"), undefined, "another module's key: undefined");
        assertEqual(module.value("lockscreen.enabled"), undefined, "a core key: undefined");
        assertEqual(module.settingKey("greeting"), "mod.good.greeting", "settingKey()");
        assert(module.setValue("greeting", 5) !== "", "setValue: a number for a text is refused");
        assert(module.setValue("undeclared", "x") !== "", "setValue: an undeclared key is refused");
        assert(module.setValue("lockscreen.enabled", false) !== "", "setValue: a core key is refused");
        assertEqual(module.setValue("greeting", "hi there"), "", "setValue: written (in the profile in effect)");
        assertEqual(module.value("greeting"), "hi there", "… and read back");
        assertEqual(module.setValue("loud", true), "", "setValue: a global setting");
        assertEqual(module.value("loud"), true, "… read back");
        module.setValue("greeting", "hello");
        module.setValue("loud", false);

        // --- facts ---
        assertEqual(module.facts["good.ready"], true, "the fact its main set");
        assert(module.setFact("level", 150) !== "", "setFact: a percent above 100 refused");
        assert(module.setFact("ready", "yes") !== "", "setFact: a text for a bool refused");
        assert(module.setFact("undeclared", 1) !== "", "setFact: an undeclared fact refused");
        assert(module.setFact("battery.percent", 1) !== "", "setFact: a core fact refused");
        assertEqual(module.setFact("level", 42), "", "setFact: a declared fact");
        assertEqual(module.facts["good.level"], 42, "… there");
        assertEqual(module.setFact("good.level", null), "", "setFact: null — not known");
        assertEqual(module.facts["good.level"], null, "… null");

        // --- its store ---
        assert(module.store.ready, "the store is read");
        assert(module.store.get("starts", 0) >= 1, "the main counted its start in the store");
        assert(module.store.set("token", { value: "abc", expires: 5 }), "set: plain JSON");
        assertEqual(module.store.get("token").value, "abc", "get");
        assertEqual(module.store.get("absent", "fallback"), "fallback", "get: a fallback");
        assert(!module.store.set("huge", "x".repeat(2 * 1024 * 1024)), "set: refused past the size limit");
        assert(module.store.remove("token") && module.store.get("token") === undefined, "remove");

        // --- commands, the shell's way ---
        action.run(["sh", standIn, "a b", "c"], result => suite._results.plain = result);
        action.run(["sh", standIn], result => suite._results.code = result, { STAND_IN_EXIT: "3" });
        // Test mode: the real pkexec is never started — not the default "pkexec", not one on
        // PATH (tests/run-modules.sh puts one there that fails the run), not through the
        // runner either; only its stand-in, module.programs.pkexec
        admin.run(["/bin/sh", standIn, "as root"], "Default pkexec", result => suite._results.defaultElevate = result);
        runner.start(["pkexec", "/bin/true"], { done: result => suite._results.runnerPkexec = result });
        action.run(["/usr/bin/pkexec", "/bin/true"], result => suite._results.actionPkexec = result);
        // … nor handed on to another program: every word of the command is looked at
        runner.start(["env", "pkexec", "/bin/true"], { done: result => suite._results.envPkexec = result });
        runner.start(["timeout", "5", "pkexec", "/bin/true"], { done: result => suite._results.timeoutPkexec = result });
        action.run(["setsid", "/run/wrappers/bin/pkexec", "/bin/true"], result => suite._results.setsidPkexec = result);
        // A 1.10 module is under the strict rule: an elevating program that is not its
        // <testPrograms>/pkexec is refused even when it is no real pkexec — the stand-in that
        // the gate lets an older module use (tests/fixtures/modules/legacy-elevate) is not its
        outsider.elevate = [String(Qt.resolvedUrl("../../../legacy-tools/pkexec")).replace(/^file:\/\//, "")];
        outsider.run(["/bin/sh", standIn, "as root"], "Another elevating program", result => suite._results.outsider = result);
        admin.elevate = [module.programs.pkexec.path];
        admin.run(["/bin/sh", standIn, "as root"], "Running the stand-in", result => suite._results.root = result);
        // The command read once: a word that changes after its first read runs as first read
        const switching = ["/bin/sh", standIn, "as root"];
        let switchReads = 0;
        Object.defineProperty(switching, 2, { get() { return ++switchReads === 1 ? "as root" : "switched"; }, enumerable: true });
        admin.run(switching, "Read once", result => suite._results.readOnce = result);
        admin.run(["/bin/sh", standIn], "Dismissing", result => suite._results.dismissed = result, { FAKE_PKEXEC_EXIT: "126" });
        admin.run(["/bin/sh", standIn], "Refusing", result => suite._results.refused = result, { FAKE_PKEXEC_EXIT: "127" });
        // API 1.2: a program that is not there, or not given by an absolute path, is notFound —
        // never shown as "not authorised" (pkexec would exit 127 for it); pkexec not asked
        admin.run(["/nonexistent/h2s-no-such-program"], "Missing", result => suite._results.missing = result, { FAKE_PKEXEC_EXIT: "127" });
        admin.run(["sh", standIn], "Relative", result => suite._results.relative = result);
        admin.run("not a list", "Nothing", result => suite._results.bad = result);
        query.command = ["sh", standIn, "queried"];
        query.request();
        // API 1.8
        runner.start(["sh", standIn, "one two", "three"], {
            timeoutMs: 5000,
            environment: { STAND_IN_EXIT: "5" },
            onLine: (line, stream) => suite._ranLines.push(stream + ":" + line),
            done: result => suite._ran = result
        });

        _then("the commands answered", () => Object.keys(_results).length === 16 && _queried !== null, () => {
            assert(!_results.defaultElevate.ok && _results.defaultElevate.error.startsWith("test mode:") && !_results.defaultElevate.refused,
                   "PrivilegedAction in test mode: the default pkexec refused, nothing run: " + JSON.stringify(_results.defaultElevate));
            assert(!_results.runnerPkexec.ok && _results.runnerPkexec.error.startsWith("test mode:"),
                   "CommandRunner in test mode: a pkexec on PATH refused: " + JSON.stringify(_results.runnerPkexec));
            assert(!_results.actionPkexec.ok && _results.actionPkexec.error.startsWith("test mode:"),
                   "CommandAction in test mode: /usr/bin/pkexec refused: " + JSON.stringify(_results.actionPkexec));
            for (const name of ["envPkexec", "timeoutPkexec", "setsidPkexec"])
                assert(!_results[name].ok && _results[name].error.startsWith("test mode:"),
                       name + ": a pkexec handed to env, timeout or setsid refused: " + JSON.stringify(_results[name]));
            assert(!_results.outsider.ok && _results.outsider.error.startsWith("test mode:") && _results.outsider.code === -1,
                   "PrivilegedAction from a 1.10 module: an elevating program that is not its stand-in pkexec refused: " + JSON.stringify(_results.outsider));
            assert(_results.plain.ok && JSON.stringify(_results.plain.lines) === "[\"a b\",\"c\"]", "CommandAction: its lines, arguments kept whole");
            assertEqual(_results.code.code, 3, "CommandAction: the exit status (environment passed)");
            assert(_results.root.ok && _results.root.lines[0] === "as root", "PrivilegedAction: run through the elevating program");
            assert(_results.readOnce.ok && JSON.stringify(_results.readOnce.lines) === "[\"as root\"]",
                   "PrivilegedAction: the command read once, what was checked is what ran: " + JSON.stringify(_results.readOnce.lines));
            assert(_results.dismissed.dismissed && !_results.dismissed.ok, "PrivilegedAction: 126 is dismissed");
            assert(_results.refused.refused && !_results.refused.dismissed, "PrivilegedAction: 127 is refused");
            assert(!_results.bad.ok, "PrivilegedAction: not a command — refused, answered");
            assert(_results.missing.notFound && !_results.missing.refused && !_results.missing.dismissed && !_results.missing.ok,
                   "PrivilegedAction: a missing program is notFound, not refused: " + JSON.stringify(_results.missing));
            assert(_results.relative.notFound && !_results.relative.refused, "PrivilegedAction: a relative path is notFound (an absolute path is required)");
            assert(!_results.root.notFound && _results.refused.notFound === false, "PrivilegedAction: notFound false when the program is there");
            assertEqual(JSON.stringify(_queried), "[\"queried\"]", "CommandQuery: its lines");
        });
        _then("the runner's command answered", () => _ran !== null, () => {
            assertEqual(_ran.ok + " " + _ran.code + " " + _ran.timedOut + " " + _ran.failedToStart + " " + _ran.error, "false 5 false false ",
                        "CommandRunner: the exit status (the run's environment passed), nothing else said");
            assertEqual(_ran.stdout + "|" + _ranLines.join(), "one two\nthree|stdout:one two,stdout:three", "CommandRunner: its output, whole and line by line, arguments kept whole");
            assertEqual(runner.running, 0, "CommandRunner: no run left");
            // Last: turned off and on as Settings → Modules does (ModuleTestKit.setEnabled)
            assertEqual(ModuleTestKit.setEnabled("Not An Id", false), false, "ModuleTestKit.setEnabled: not a module id, refused");
            assert(ModuleTestKit.setEnabled("good", false), "ModuleTestKit.setEnabled(good, false)");
        });
        _then("it is turned off", () => !module.active && ModuleTestKit.status("good")?.state === "disabled", () => {
            assert(!ModuleTestKit.widgetEntries.some(entry => entry.module === "good"), "off: its widget is gone");
            assert(ModuleTestKit.setEnabled("good", true), "ModuleTestKit.setEnabled(good, true)");
        });
        _then("it is on again", () => module.active && ModuleTestKit.status("good")?.state === "loaded", () => {
            assert(ModuleTestKit.widgetEntries.some(entry => entry.module === "good"), "on again: its widget is back");
        });
    }
}
