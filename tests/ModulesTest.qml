import QtQuick
import Quickshell
import qs.singletons

// The module host (singletons/ModuleHost.qml) pointed at the fixture modules
// (tests/fixtures/modules) through its seam, load(directories): each fixture's status, the
// merged lists, the guard (broken and broken-main do not touch good), the two spellings of one
// directory, turning a module off and on (Config.disabledModules — never written: the runner's
// Config is read-only), safe mode, and hostile input. Asynchronous: the check of required
// programs is a process.
TestCase {
    id: suite
    suiteName: "Modules"
    asynchronous: true

    readonly property string fixtures: Quickshell.shellDir + "/tests/fixtures/modules"
    readonly property var names: ["good", "broken", "broken-main", "wrong-api", "key-collision", "bad-manifest",
                                  "bad-manifest-fields", "forbidden-import", "duplicate-id", "duplicate-id-2", "needs-program"]

    property ModuleHost host: ModuleHost {
        logStates: false
    }
    property var _savedDisabled: []
    property var _steps: []
    property var _created: []

    // ---- A tiny scheduler: each step waits for its condition (or its deadline), then runs ----

    function _then(description, condition, action, timeoutMs) {
        _steps.push({ description: description, condition: condition, action: action, deadline: timeoutMs ?? 10000 });
    }

    property Timer _clock: Timer {
        interval: 25
        repeat: true
        property int waited: 0
        onTriggered: {
            const step = suite._steps[0];
            if (!step) {
                stop();
                suite._end();
                return;
            }
            waited += interval;
            let ready = false;
            try {
                ready = step.condition();
            } catch (error) {
                ready = false;
            }
            if (!ready && waited < step.deadline)
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

    function _end() {
        Config.disabledModules = _savedDisabled;
        host.unload();
        for (const object of _created)
            object?.destroy();
        finish();
    }

    // ---- Helpers ----

    function _dirs(list) {
        return list.map(name => fixtures + "/" + name);
    }

    function _status(directoryName) {
        return host.statuses.find(status => status.directory === fixtures + "/" + directoryName) ?? null;
    }

    function _settled() {
        return host.statuses.length > 0 && !host.statuses.some(status => status.state === "pending") && !host.checkingPrograms;
    }

    function _has(list, fragment) {
        return (list ?? []).some(entry => String(entry).includes(fragment));
    }

    function _expectState(directoryName, state) {
        const status = _status(directoryName);
        assertEqual(status?.state, state, directoryName + ": " + state + (status && status.state !== state ? " (errors: " + status.errors.join("; ") + ")" : ""));
        return status;
    }

    function runAsync() {
        _savedDisabled = host._plainList(Config.disabledModules);
        Config.disabledModules = [];

        // Every fixture, and good twice more in other spellings of its directory
        _then("the config is read", () => Config.ready, () => {
            host.load(_dirs(names).concat([fixtures + "//good", fixtures + "/./good/"]), {});
            assertEqual(host.directories.length, names.length, "one directory, one module: other spellings of good's directory are the same directory");
        });
        _then("the program check answers", _settled, () => {
            assertEqual(host.statuses.length, names.length, "a status for each fixture directory");

            const good = _expectState("good", "loaded");
            assertEqual(good?.errors.length, 0, "good: no errors");
            assertEqual(good?.warnings.length, 0, "good: no warnings");
            assertEqual(good?.version + " " + good?.api + " " + good?.name, "1.2.3 1.0 Good fixture", "good: version, API, name");
            assertEqual(good?.directory, fixtures + "/good", "good: its canonical directory");
            const main = host.mainObject("good");
            assert(main !== null, "good: its main was created");
            assertEqual(main?.goodState.mains, 1, "good: one main, once (the two other spellings did not load it again)");

            const broken = _expectState("broken", "failed");
            assert(_has(broken?.errors, "Main.qml:5"), "broken: the syntax error, with its file and line: " + broken?.errors.join("; "));
            assertEqual(host.mainObject("broken"), null, "broken: no main");

            _expectState("broken-main", "loaded");
            assert(host.mainObject("broken-main") !== null,
                   "broken-main: an exception in Component.onCompleted is the engine's to print; the host cannot see it, the object exists");

            const wrongApi = _expectState("wrong-api", "incompatible");
            assert(_has(wrongApi?.errors, "2.0") && _has(wrongApi?.errors, "1.0"), "wrong-api: says which API it wants and which the shell has");

            const collision = _expectState("key-collision", "loaded");
            assert(_has(collision?.errors, "lockscreen.enabled"), "key-collision: the core's key dropped, with an error");
            assert(_has(collision?.errors, "mod.good.greeting"), "key-collision: another module's key dropped, with an error");
            assert(_has(collision?.errors, "battery.percent"), "key-collision: the core's fact dropped, with an error");
            assert(_has(collision?.errors, "\"clock\""), "key-collision: the core's widget type dropped, with an error");

            const notJson = _expectState("bad-manifest", "failed");
            assert(_has(notJson?.errors, "not valid JSON"), "bad-manifest: not JSON, said so");
            const fields = _expectState("bad-manifest-fields", "failed");
            assert(_has(fields?.errors, "\"name\"") && _has(fields?.errors, "\"api\"") && _has(fields?.errors, "version"),
                   "bad-manifest-fields: the missing and malformed fields named: " + fields?.errors.join("; "));
            assertEqual(fields?.id, "bad-manifest-fields", "bad-manifest-fields: its id still shown");

            const forbidden = _expectState("forbidden-import", "loaded");
            assert(_has(forbidden?.warnings, "imports qs.singletons"), "forbidden-import: loaded, with a warning naming the import");
            assertEqual(forbidden?.errors.length, 0, "forbidden-import: a warning, not an error");

            _expectState("duplicate-id", "loaded");
            const second = _expectState("duplicate-id-2", "duplicate");
            assertEqual(second?.shadowedBy, fixtures + "/duplicate-id", "duplicate-id-2: shadowed by the first, which is named");
            assertEqual(second?.id, "duplicate-id", "duplicate-id-2: its id shown");
            assertEqual(host.status("duplicate-id")?.version, "1.0.0", "status(id) gives the one that counts");

            const needs = _expectState("needs-program", "missing-program");
            assertEqual(JSON.stringify(needs?.missingPrograms), "[\"h2s-fixture-no-such-program\"]", "needs-program: only the missing program (sh is there)");
            assertEqual(needs?.setupHints.length, 1, "needs-program: its setup hint shown");
            assertEqual(host.mainObject("needs-program"), null, "needs-program: no main");

            // The merged lists: only loaded modules, by id
            assertEqual(host.widgetEntries.map(entry => entry.module + ":" + entry.type).join(","), "good:good,key-collision:key-collision",
                        "widgetEntries: good's and key-collision's own, by id");
            assertEqual(host.widgetEntries[0]?.widget, "file://" + fixtures + "/good/GoodWidget.qml", "… with absolute URLs");
            assertEqual(host.settingEntries.map(entry => entry.key).join(","), "mod.good.greeting,mod.key-collision.fine", "settingEntries");
            assertEqual(host.factTypes.map(entry => entry.fact).join(","), "good.ready,key-collision.fine", "factTypes");
            assertEqual(host.settingsPages.map(entry => entry.id).join(","), "good", "settingsPages");
            assertEqual(host.slotContributions("network.vpn.row").map(entry => entry.module).join(","), "good", "slotContributions");
            assertEqual(host.slotContributions("network.vpn.card").length, 0, "… none for an empty slot");

            // A module file the core will load from those URLs shares the module's singleton
            const component = Qt.createComponent(host.widgetEntries[0].widget, Component.PreferSynchronous);
            const widget = component.status === Component.Ready ? component.createObject(suite) : null;
            _created.push(widget);
            assert(widget !== null && widget.goodState === main.goodState,
                   "a widget loaded from widgetEntries shares the singleton good's main uses");

            const description = JSON.parse(JSON.stringify(host.describe()));
            assertEqual(description.api + " " + description.safeMode + " " + description.modules.length, "1.0 false " + names.length,
                        "describe(): the IPC's JSON, plain data");

            // Turning good off: its main destroyed, its contributions gone, in the config
            suite._goodState = main.goodState;
            assert(host.setEnabled("good", false), "setEnabled(good, false)");
            assert(host._plainList(Config.disabledModules).includes("good"), "… stored in Config.disabledModules");
        });
        _then("good is disabled", () => _status("good")?.state === "disabled" && _goodState.mains === 0, () => {
            assertEqual(_status("good")?.enabled, false, "disabled: enabled false in its status");
            assertEqual(host.mainObject("good"), null, "disabled: no main");
            assertEqual(_goodState.mains, 0, "disabled: its main was destroyed (its onDestruction ran)");
            assertEqual(host.widgetEntries.map(entry => entry.module).join(","), "key-collision", "disabled: its widget gone");
            assertEqual(host.slotContributions("network.vpn.row").length, 0, "disabled: its slot contribution gone");
            assertEqual(_status("broken-main")?.state, "loaded", "the others untouched");
            assert(host.setEnabled("good", true), "setEnabled(good, true)");
        });
        _then("good is loaded again", () => _status("good")?.state === "loaded", () => {
            assert(host.mainObject("good") !== null, "enabled again: a new main");
            assertEqual(_goodState.mains, 1, "… one");
            assertEqual(_goodState.started, 2, "… created a second time (the module's singleton lives on)");
            assertEqual(host.widgetEntries.map(entry => entry.module).join(","), "good,key-collision", "… its widget back");
            assert(!host._plainList(Config.disabledModules).includes("good"), "… and out of Config.disabledModules");
            assertEqual(host.setEnabled("Not An Id", false), false, "setEnabled refuses what is not a module id");

            // Safe mode: manifests read, nothing loaded
            host.load(_dirs(names), { safeMode: true });
        });
        _then("safe mode settles", () => host.statuses.length > 0 && _goodState.mains === 0, () => {
            assert(host.safeMode, "safe mode on");
            _expectState("good", "safe-mode");
            _expectState("needs-program", "safe-mode");
            _expectState("broken", "safe-mode");
            _expectState("bad-manifest", "failed");
            _expectState("wrong-api", "incompatible");
            assertEqual(host.mainObject("good"), null, "safe mode: no main");
            assertEqual(host.widgetEntries.length + host.settingEntries.length + host.factTypes.length + host.settingsPages.length, 0,
                        "safe mode: no contributions");

            // Hostile input: nothing throws, the host stays usable
            for (const input of [null, undefined, 42, {}, "relative:also/relative", [null, 7, ""], "/"]) {
                host.load(input, {});
                assertEqual(host.statuses.length, 0, "load(" + JSON.stringify(input) + "): no module, no throw");
            }
            assertEqual(host.hostError, "", "… and the host did not fail");
            host.load("/nonexistent-h2s-module:" + fixtures + "/good", {});
            const missing = host.statuses[0];
            assertEqual(missing?.state, "failed", "a directory without module.json: failed");
            assert(_has(missing?.errors, "module.json cannot be read"), "… said so: " + missing?.errors.join("; "));
            assertEqual(host.directories.length, 2, "a colon-separated list, as in H2S_SHELL_MODULES");
        });
        _then("good loads from a colon-separated list", () => _status("good")?.state === "loaded", () => {
            assertEqual(_goodState.mains, 1, "good loaded beside a missing directory");
            host.unload();
        });
        _then("unloaded", () => _goodState.mains === 0, () => {
            assertEqual(host.statuses.length, 0, "unload(): no statuses");
            assertEqual(_goodState.mains, 0, "unload(): the main destroyed");
        });
        _clock.start();
    }

    property var _goodState: null
}
