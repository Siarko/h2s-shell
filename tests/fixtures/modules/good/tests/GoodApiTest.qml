import QtQuick
import qs.api
import qs.tests
import ".."

// The module API from a module's side (tests/run-modules.sh): only qs.api (and the shell's
// TestCase) — its handle, its settings, facts, store, the theme, the slot table, commands
// through the API's helpers against stand-in programs (tests/stand-in.sh, fake-pkexec.sh)
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
    property CommandQuery query: CommandQuery {
        onDone: lines => suite._queried = lines
    }
    property var _queried: null
    property var _results: ({})

    function runAsync() {
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
        assertEqual(Api.version, "1.0", "Api.version");
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
        admin.elevate = ["sh", module.directory + "/tests/fake-pkexec.sh"];
        admin.run(["sh", standIn, "as root"], "Running the stand-in", result => suite._results.root = result);
        admin.run(["126"], "Dismissing", result => suite._results.dismissed = result);
        admin.run(["127"], "Refusing", result => suite._results.refused = result);
        admin.run("not a list", "Nothing", result => suite._results.bad = result);
        query.command = ["sh", standIn, "queried"];
        query.request();

        _then("the commands answered", () => Object.keys(_results).length === 6 && _queried !== null, () => {
            assert(_results.plain.ok && JSON.stringify(_results.plain.lines) === "[\"a b\",\"c\"]", "CommandAction: its lines, arguments kept whole");
            assertEqual(_results.code.code, 3, "CommandAction: the exit status (environment passed)");
            assert(_results.root.ok && _results.root.lines[0] === "as root", "PrivilegedAction: run through the elevating program");
            assert(_results.dismissed.dismissed && !_results.dismissed.ok, "PrivilegedAction: 126 is dismissed");
            assert(_results.refused.refused && !_results.refused.dismissed, "PrivilegedAction: 127 is refused");
            assert(!_results.bad.ok, "PrivilegedAction: not a command — refused, answered");
            assertEqual(JSON.stringify(_queried), "[\"queried\"]", "CommandQuery: its lines");
        });
        _clock.start();
    }
}
