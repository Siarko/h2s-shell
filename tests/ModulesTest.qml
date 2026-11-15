import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.api

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
                                  "bad-manifest-fields", "forbidden-import", "duplicate-id", "duplicate-id-2", "needs-program",
                                  "broken-slot", "link-escape"]

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
            assert(_has(wrongApi?.errors, "2.0") && _has(wrongApi?.errors, Api.version), "wrong-api: says which API it wants and which the shell has");

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

            const escape = _expectState("link-escape", "failed");
            assert(_has(escape?.errors, "main Main.qml leaves the module directory"), "link-escape: a main that links out of the module fails it, never loaded: " + escape?.errors.join("; "));
            assertEqual(host.mainObject("link-escape"), null, "link-escape: no main");
            const brokenSlot = _expectState("broken-slot", "loaded");
            assertEqual(brokenSlot?.errors.length, 0, "broken-slot: loaded — its slot file is only built where the slot is");

            // The merged lists: only loaded modules, by id
            assertEqual(host.widgetEntries.map(entry => entry.module + ":" + entry.type).join(","), "good:good,key-collision:key-collision",
                        "widgetEntries: good's and key-collision's own, by id (link-escape's never: it failed)");
            assertEqual(host.widgetEntries[0]?.widget, "file://" + fixtures + "/good/GoodWidget.qml", "… with absolute URLs");
            assertEqual(host.settingEntries.map(entry => entry.key).join(","), "mod.good.greeting,mod.good.loud,mod.key-collision.fine", "settingEntries");
            assertEqual(host.factTypes.map(entry => entry.fact).join(","), "good.ready,good.level,key-collision.fine", "factTypes");
            assertEqual(host.settingsPages.map(entry => entry.id).join(","), "good", "settingsPages");
            assertEqual(host.slotContributions("network.popup.sections").map(entry => entry.module).join(","), "good", "slotContributions");
            assertEqual(host.slotContributions("network.vpn.card").length, 0, "… none for an empty slot");

            // A module file the core will load from those URLs shares the module's singleton
            const component = Qt.createComponent(host.widgetEntries[0].widget, Component.PreferSynchronous);
            const widget = component.status === Component.Ready ? component.createObject(suite) : null;
            _created.push(widget);
            assert(widget !== null && widget.goodState === main.goodState,
                   "a widget loaded from widgetEntries shares the singleton good's main uses");

            const description = JSON.parse(JSON.stringify(host.describe()));
            assertEqual(description.api + " " + description.safeMode + " " + description.modules.length, Api.version + " false " + names.length,
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
            assertEqual(host.slotContributions("network.popup.sections").length, 0, "disabled: its slot contribution gone");
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
        _then("safe mode settles", () => _settled() && _goodState.mains === 0, () => {
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

            // A FIFO as a module's main, and as a widget of another: never opened (opening one
            // blocks the GUI thread until something writes to it)
            _sh("rm -rf \"$1\"; mkdir -p \"$1/fifo-main\" \"$1/fifo-widget\" && "
                + "printf '{\"id\":\"fifo-main\",\"name\":\"F\",\"version\":\"1\",\"api\":\"1.0\",\"main\":\"Main.qml\"}' > \"$1/fifo-main/module.json\" && "
                + "printf '{\"id\":\"fifo-widget\",\"name\":\"F\",\"version\":\"1\",\"api\":\"1.0\",\"widgets\":[{\"type\":\"fifo-widget\",\"name\":\"F\",\"widget\":\"W.qml\"}]}' > \"$1/fifo-widget/module.json\" && "
                + "mkfifo \"$1/fifo-main/Main.qml\" \"$1/fifo-widget/W.qml\" && printf '123:8 1\\n' > \"$1/starts\"", [_scratch], code => suite._made = code);
        });
        _then("the FIFO modules are made", () => _made !== null, () => {
            assertEqual(_made, 0, "made the FIFO fixtures");
            host.load([_scratch + "/fifo-main", _scratch + "/fifo-widget"], {});
        });
        _then("the FIFO modules settle", _settled, () => {
            const fifoMain = host.statuses.find(status => status.id === "fifo-main");
            assertEqual(fifoMain?.state, "failed", "a FIFO as main: the module fails (and nothing hung)");
            assert(_has(fifoMain?.errors, "not a regular file"), "… said so: " + fifoMain?.errors.join("; "));
            const fifoWidget = host.statuses.find(status => status.id === "fifo-widget");
            assertEqual(fifoWidget?.state, "loaded", "a FIFO as a widget: the module loads");
            assert(_has(fifoWidget?.errors, "widget fifo-widget: W.qml is not a regular file (dropped)"), "… without that widget: " + fifoWidget?.errors.join("; "));
            assertEqual(host.widgetEntries.length, 0, "… which is in no list");

            // The start guard, with a counter file of the test's and an identity it gives:
            // process 123 relaunched once after a crash already (8), now again (9)
            host.guardFile = _scratch + "/starts";
            host.guardIdentity = "123:9";
            host.guardClearMs = 300;
            host.load(_dirs(["good"]), {});
        });
        _then("the guarded load settles", () => _settled() && host.guard !== null, () => {
            assert(host.safeMode, "a second relaunch after a crash in a row: safe mode");
            assertEqual(host.guard?.count, 2, "… the count");
            assert(_has([host.safeModeReason], "relaunched the shell after a crash 2 times"), "… and why, for `modules list`: " + host.safeModeReason);
            _expectState("good", "safe-mode");
            assertEqual(host.describe().safeModeReason, host.safeModeReason, "describe() tells it");
            // A reload of the same relaunched process: counted once, not again
            host.load(_dirs(["good"]), {});
        });
        _then("the reload settles", () => _settled() && host.guard !== null, () => {
            assertEqual(host.guard?.count, 2, "a reload of the same process: not counted again");
            suite._exists = null;
            _sh("sleep 0.6; cat \"$1/starts\"", [_scratch], (code, output) => suite._exists = output.trim());
        });
        _then("the counter is cleared after the window", () => _exists !== null, () => {
            assertEqual(_exists, "123:9 0", "lived guardClearMs: the count back to 0");
            suite._made = null;
            _sh("printf 'garbage\\n' > \"$1/starts\"", [_scratch], code => suite._made = code);
        });
        _then("garbage in the counter", () => _made !== null, () => {
            host.guardIdentity = "123:10";
            host.load(_dirs(["good"]), {});
        });
        _then("garbage settles", () => _settled() && host.guard !== null, () => {
            assert(!host.safeMode, "a counter that is garbage: this relaunch counts as the first");
            _expectState("good", "loaded");
            suite._exists = null;
            _sh("cat \"$1/starts\"", [_scratch], (code, output) => suite._exists = output.trim());
        });
        _then("counted", () => _exists !== null, () => {
            assertEqual(_exists, "123:10 1", "… written: 1");
            // A fresh process (no crash marker: a launch, a --restart): 0, whatever was there
            host.guardIdentity = "456:";
            host.load(_dirs(["good"]), {});
        });
        _then("a fresh process settles", () => _settled() && host.guard !== null, () => {
            assertEqual(host.guard?.count, 0, "a fresh process: 0");
            assert(!host.safeMode, "… no safe mode");
            host.guardFile = "";
            host.unload();
            _sh("rm -rf \"$1\"", [_scratch], () => {});
        });
        _clock.start();
    }

    property var _goodState: null
    property var _made: null
    property var _exists: null
    // The test's own files: in the private runtime directory the runner gives it
    readonly property string _scratch: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/h2s-modules-test-" + Date.now()

    // Runs a shell script with arguments; done(exit code, output)
    function _sh(script, args, done) {
        const process = _shell.createObject(suite, { command: ["sh", "-c", script, "sh"].concat(args), done: done });
        process.running = true;
    }

    property Component _shell: Component {
        Process {
            id: _process
            property var done: null
            property string output: ""
            stdout: SplitParser {
                splitMarker: ""
                onRead: data => _process.output += data
            }
            onExited: code => {
                _process.done?.(code, _process.output);
                _process.destroy();
            }
        }
    }
}
