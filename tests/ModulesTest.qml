import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons
import qs.api
import qs.components

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
    // It turns modules off and on through Config.disabledModules, as other suites do
    ownProcess: true

    readonly property string fixtures: Quickshell.shellDir + "/tests/fixtures/modules"
    readonly property var names: ["good", "broken", "broken-main", "wrong-api", "key-collision", "bad-manifest",
                                  "bad-manifest-fields", "forbidden-import", "duplicate-id", "duplicate-id-2", "needs-program",
                                  "broken-slot", "link-escape"]

    property ModuleHost host: ModuleHost {
        logStates: false
    }
    property var _savedDisabled: []
    property var _privilegedAnswers: ({})
    property string _savedAcknowledged: ""
    property var _savedEnabled: []
    property string _mark: ""
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
        Config.setAcknowledgedModulesText(_savedAcknowledged);
        Config.enabledModules = _savedEnabled;
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
        _savedAcknowledged = Config.acknowledgedModulesText;
        _savedEnabled = host._plainList(Config.enabledModules);

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
            assertEqual(JSON.stringify(good?.deprecations ?? null), "[]", "good: on qs.api alone, nothing deprecated");
            assertEqual(good?.version + " " + good?.api + " " + good?.name, "1.2.3 1.36 Good fixture", "good: version, API, name");
            // (1.26) Its icon, an SVG painted in the theme's colour: on its handle as the shell draws it
            assertEqual(JSON.stringify(host.handle("good").icon),
                        JSON.stringify({ kind: "svg", glyph: "", url: "file://" + fixtures + "/good/icon.svg", colors: "theme" }),
                        "good: its icon on its handle, the file by its URL");
            assert(Object.isFrozen(host.handle("good").icon), "… frozen");
            assertEqual(host.handle("broken-main").icon, null, "a module with no icon: null on its handle");
            assertEqual(good?.directory, fixtures + "/good", "good: its canonical directory");
            const main = host.mainObject("good");
            assert(main !== null, "good: its main was created");
            assertEqual(main?.goodState.mains, 1, "good: one main, once (the two other spellings did not load it again)");

            // module.log (API 1.12): with a key, once per change of text
            const goodHandle = host.handle("good");
            assertEqual(goodHandle.dataDirectory, "", "no dataRoot (the suites' default), not in test mode: module.dataDirectory \"\", nothing made");
            assert(goodHandle.log("info", "reading the state failed: no answer", "state"), "log: a key's first line is written");
            assert(!goodHandle.log("info", "reading the state failed: no answer", "state"), "log: the same text for the key again, not written");
            assert(!goodHandle.log("info", "reading the state failed: no\nanswer", "state"), "… also with a line break where the space was");
            assert(goodHandle.log("error", "reading the state failed: no answer", "state"), "log: the same text at another level, written");
            assert(!goodHandle.log("error", "reading the state failed: no answer", "state"), "… and then not again");
            assert(goodHandle.log("info", "reading the state failed: refused", "state"), "log: the key's text changed, written");
            assert(goodHandle.log("info", "reading the state failed: no answer", "other"), "log: another key has its own memory");
            assert(goodHandle.log("info", "the state answers again", "state"), "log: the recovery, written");
            assert(goodHandle.log("info", "no key") && goodHandle.log("info", "no key") && goodHandle.log("info", "no key", ""),
                   "log: without a key, every line");
            assert(goodHandle.log("error", "refused \u0007 once", "state") && goodHandle.log("whatever", "a level it does not know"), "log: every level, an unknown one too");
            const entry = ModuleRules.logEntry("good", "loud", "a\nb\u001b[0m" + "x".repeat(2000), "k", new Map([["k", "old"]]));
            assertEqual(entry.level + "|" + entry.key + "|" + entry.write, "info|k|true", "logEntry: an unknown level is info; a changed text is written");
            assert(entry.line.startsWith("[good] a b[0mxx") && Array.from(entry.text).length === ModuleRules.logTextCap && entry.text.endsWith("…"),
                   "logEntry: \"[<id>]\", one line, control characters dropped, cut: " + entry.line.slice(0, 30));
            assertEqual(ModuleRules.logEntry("good", "info", "evil\u202etxt a\u200db \ufeffc\u2028d\u2029e\u2066f\u2069 😀").text, "eviltxt ab c d ef 😀",
                        "logEntry: format characters dropped (an override, a joiner, a BOM, isolates), separators as spaces, an emoji kept");
            assertEqual(ModuleRules.logEntry("good", "info", "same", "k", new Map([["k", "info:same"]])).write, false, "logEntry: the key's last level and text again → not written");
            assertEqual(ModuleRules.logEntry("good", "warn", "same", "k", new Map([["k", "info:same"]])).write, true, "logEntry: the same text at another level → written");
            assertEqual(ModuleRules.logEntry("good", "info", "same", "", new Map([["", "same"]])).write, true, "logEntry: no key → always written");
            assertEqual(ModuleRules.logEntry("good", "info", "same", "k", { k: "same" }).write, true, "logEntry: a memory that is not a Map → none");
            assertEqual(ModuleRules.logEntry("good", "info", { toString: () => "x" }).text, "", "logEntry: text that is not a string or number → empty");
            // debug: written only with the debug setting on, and not remembered while it is off
            assertEqual(ModuleRules.logEntry("good", "debug", "d", "k", new Map(), false).write, false, "logEntry: a debug line, debug off → not written");
            assertEqual(ModuleRules.logEntry("good", "debug", "d", "k", new Map(), true).write, true, "logEntry: a debug line, debug on → written");
            assert(Profiles.value("general.debug") !== true, "the test config has debug off");
            assert(!goodHandle.log("debug", "a debug line", "debug-key"), "log: a debug line with debug off → false");
            assert(!goodHandle._logWritten.has("debug-key"), "… and not remembered, so it is written once debug is on");
            for (let i = 0; i < ModuleRules.maxLogKeys + 5; i++)
                goodHandle.log("info", "line", "key" + i);
            assertEqual(goodHandle._logWritten.size, ModuleRules.maxLogKeys, "log: at most maxLogKeys keys remembered");
            assert(!goodHandle._logWritten.has("key0") && goodHandle._logWritten.has("key" + (ModuleRules.maxLogKeys + 4)), "… the oldest dropped first");
            assertEqual(ModuleRules.minuteStart(1731400012345) + "|" + ModuleRules.minuteStart(NaN) + "|" + ModuleRules.minuteStart("5"), "1731399960000|0|0",
                        "minuteStart: the minute's start; not a number: 0");

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
            assertEqual(JSON.stringify(forbidden?.errors), JSON.stringify(["Main.qml imports qs.singletons, the shell's own: a module reaches the shell through qs.api",
                                                                          "sections/reach.js imports qs.singletons, the shell's own: a module reaches the shell through qs.api"]),
                        "forbidden-import: loaded, the shell's singletons imported an error naming the file and the import — a script's .import too");
            assert(!_has(forbidden?.warnings, "qs.singletons"), "… not a warning");
            assert(_has(forbidden?.warnings, "sections/deeper/Deeper.qml imports Quickshell.Hyprland"),
                   "forbidden-import: a QML file in a subdirectory, named nowhere, is scanned too: " + JSON.stringify(forbidden?.warnings));
            assert(_has(forbidden?.deprecations, "qs.components (in sections/Section.qml)"),
                   "… and its deprecated import listed: " + JSON.stringify(forbidden?.deprecations));
            assert(!_has(forbidden?.warnings, "qs.panels"), "… but not one in a hidden directory");
            assertEqual(JSON.stringify(forbidden?.deprecations.filter(line => !line.startsWith("import "))),
                        JSON.stringify(["Api.module(id) (in 2 files): use `Api.moduleStatus(id)` for another module's state, and its `exports` through `uses` (goes with the shell's next tightening)",
                                        "module.host (in sections/OldWays.qml): gone since API 1.36; use the handle's own properties and qs.api (in a suite, ModuleTestKit)"]),
                        "… and the old ways of reaching another module and the host, from its code (a script's too): " + JSON.stringify(forbidden?.deprecations));

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
            assertEqual(host.slotContributions("network.vpn.page").map(entry => entry.module).join(","), "broken-slot,good", "slotContributions, by module id");
            assertEqual(host.slotContributions("network.vpn.row").length, 0, "… none for a slot nobody fills as a slot (read as its anchor)");

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
            assertEqual(host.handle("good")._logWritten.size, 0, "disabled: its log keys forgotten");
            assertEqual(_goodState.mains, 0, "disabled: its main was destroyed (its onDestruction ran)");
            assertEqual(host.widgetEntries.map(entry => entry.module).join(","), "key-collision", "disabled: its widget gone");
            assertEqual(host.slotContributions("network.vpn.page").map(entry => entry.module).join(","), "broken-slot", "disabled: its slot contribution gone");
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
            assertEqual(host.safeModeCause, "launcher", "… asked for: the launcher's, for the banner's words");
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
            assertEqual(host.directories.length, 2, "a colon-separated list, as in H2S_SHELL_MODULES");
            assertEqual(host.statuses[0]?.state, "pending", "nothing read at load(): pending until the file check answers");
        });
        _then("good loads from a colon-separated list", () => _status("good")?.state === "loaded", () => {
            const missing = host.statuses[0];
            assertEqual(missing?.state, "failed", "a directory without module.json: failed");
            assert(_has(missing?.errors, "module.json cannot be read"), "… said so: " + missing?.errors.join("; "));
            assertEqual(_goodState.mains, 1, "good loaded beside a missing directory");
            host.unload();
        });
        _then("unloaded", () => _goodState.mains === 0, () => {
            assertEqual(host.statuses.length, 0, "unload(): no statuses");
            assertEqual(_goodState.mains, 0, "unload(): the main destroyed");

            // A FIFO as a module's main, and as a widget of another: never opened (opening one
            // blocks the GUI thread until something writes to it)
            _sh("rm -rf \"$1\"; mkdir -p \"$1/fifo-main\" \"$1/fifo-widget\" \"$1/manifest-only\" && "
                + "printf '{\"id\":\"manifest-only\",\"name\":\"M\",\"version\":\"1\",\"api\":\"1.0\"}' > \"$1/manifest-only/module.json\" && "
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

            // Nothing but a manifest: there is no file to check, so the manifests' answer is
            // the last thing such a module waits for (no guard, no store directory here)
            host.load([_scratch + "/manifest-only"], {});
        });
        _then("the module that is only its manifest settles", _settled, () => {
            assertEqual(host.statuses[0]?.state, "loaded", "a module that is only its module.json loads");

            // The start guard, with a counter file of the test's and an identity it gives:
            // process 123 relaunched once after a crash already (8), now again (9)
            host.guardFile = _scratch + "/starts";
            host.guardIdentity = "123:9";
            // A window no load here outlives, however slow the machine: the count is read
            // before it is cleared (a short window comes after, for the clearing)
            host.guardClearMs = 600000;
            host.load(_dirs(["good"]), {});
        });
        _then("the guarded load settles", () => _settled() && host.guard !== null, () => {
            assert(host.safeMode, "a second relaunch after a crash in a row: safe mode");
            assertEqual(host.guard?.count, 2, "… the count");
            assert(_has([host.safeModeReason], "relaunched the shell after a crash 2 times"), "… and why, for `modules list`: " + host.safeModeReason);
            assertEqual(host.safeModeCause, "relaunch", "… the start guard's, for the banner's words");
            _expectState("good", "safe-mode");
            assertEqual(host.describe().safeModeReason, host.safeModeReason, "describe() tells it");
            // A reload of the same relaunched process: counted once, not again
            host.load(_dirs(["good"]), {});
        });
        _then("the reload settles", () => _settled() && host.guard !== null, () => {
            assertEqual(host.guard?.count, 2, "a reload of the same process: not counted again");
        });
        // Inside the window the count stays: read from the file once the loads have settled,
        // so it is what the guard left, not what it is about to write
        _then("the counter read inside the window", () => _counterReads("123:9 2"), () => {
            assert(host.guard?.cleared !== true, "inside guardClearMs: not cleared");
            // Now a short window, from the next load's answer on
            host.guardClearMs = 300;
            suite._guardArmedAt = -1;
            suite._guardClearedAt = -1;
            host.load(_dirs(["good"]), {});
        });
        _then("the counter is cleared after the window", () => host.guard?.cleared === true && _counterReads("123:9 0"), () => {
            assertEqual(_counter, "123:9 0", "lived guardClearMs: the count back to 0");
            // From the answer (the window's timer armed with it) to the clearing, on a monotonic
            // clock: a loaded machine only makes it longer; Qt's coarse timers may fire 5 % early
            const lived = _guardClearedAt - _guardArmedAt;
            assert(_guardArmedAt >= 0 && lived >= 285, "… not before guardClearMs from the answer (" + lived + " ms)");
            // The long window again: the next counts are read before anything clears them
            host.guardClearMs = 600000;
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
            // No identity given, as in the running shell: the script finds the shell's own
            host.guardIdentity = "";
            host.load(_dirs(["good"]), {});
        });
        _then("the load under the shell's own identity settles", () => _settled() && host.guard !== null, () => {
            assertEqual(host.guard?.identity, Quickshell.processId + ":", "no identity given: the shell's own pid (not the pid of what the check runs inside), no crash");
            assertEqual(host.guard?.count, 0, "… a fresh process: 0");
            host.guardFile = "";
            host.unload();

            // A1: files that hang on read (a mount that answers stat, then blocks). The check's
            // `head` is a stand-in that sleeps past the deadline; load() itself reads nothing
            suite._made = null;
            _sh("mkdir -p \"$1/hung-bin\" && printf '#!/bin/sh\\nsleep 3\\nexit 1\\n' > \"$1/hung-bin/head\" && chmod +x \"$1/hung-bin/head\"",
                [_scratch], code => suite._made = code);
        });
        _then("the hanging stand-in is made", () => _made !== null, () => {
            assertEqual(_made, 0, "made the hanging head");
            host.checkEnvironment = { PATH: _scratch + "/hung-bin:" + Quickshell.env("PATH") };
            host.checkTimeoutMs = 800;
            const before = Date.now();
            host.load(_dirs(["good"]), {});
            const loadMs = Date.now() - before;
            const valueBefore = Date.now();
            const lockOnSleep = Profiles.value("lockscreen.lockOnSleep");
            const valueMs = Date.now() - valueBefore;
            assert(loadMs < 200, "load() returns at once while the module's files hang (" + loadMs + " ms)");
            assert(lockOnSleep !== undefined && valueMs < 100, "Profiles.value(\"lockscreen.lockOnSleep\") answers at once (" + valueMs + " ms): " + lockOnSleep);
            assertEqual(_status("good")?.state, "pending", "… the module pending meanwhile");
            suite._hungSince = Date.now();
        });
        _then("the hung module fails after the bound", () => _status("good")?.state === "failed", () => {
            const waited = Date.now() - _hungSince;
            assert(waited >= 600, "… not before the deadline (" + waited + " ms)");
            assert(_has(_status("good")?.errors, "module.json cannot be read") && _has(_status("good")?.errors, "within 0.8 s"),
                   "failed, with the reason: " + _status("good")?.errors.join("; "));
            assertEqual(host.mainObject("good"), null, "… nothing of it loaded");
            host.checkEnvironment = ({});
            host.checkTimeoutMs = 5000;
            host.load(_dirs(["good"]), {});
        }, 4000);
        _then("good loads again with a working check", () => _status("good")?.state === "loaded", () => {
            assertEqual(_status("good")?.warnings.length, 0, "… no warnings");
            host.unload();

            // The import scan: a module's many scanned files, slow to read (a stand-in head
            // that hangs on the scan's header reads alone), must not keep another module's
            // main from being checked; what the scan leaves out is said in the status
            suite._made = null;
            _sh("set -e; s=$1; header=$2; real_head=$(command -v head); "
                + "module() { mkdir -p \"$s/$1\"; printf '{\"id\":\"%s\",\"name\":\"S\",\"version\":\"1\",\"api\":\"1.0\",\"main\":\"Main.qml\"}' \"$1\" > \"$s/$1/module.json\"; "
                + "printf 'import QtQuick\\nQtObject {}\\n' > \"$s/$1/Main.qml\"; }; "
                + "forbidden() { mkdir -p \"$(dirname \"$1\")\"; printf 'import QtQuick\\nimport %s\\nQtObject {}\\n' \"$2\" > \"$1\"; }; "
                + "module scan-a; module scan-b; for n in 1 2 3; do forbidden \"$s/scan-a/sub/S$n.qml\" qs.singletons; done; "
                + "mkdir -p \"$s/slow-bin\"; printf '#!/bin/sh\\n[ \"$2\" = %s ] && { sleep 3; exit 1; }\\nexec %s \"$@\"\\n' \"$header\" \"$real_head\" > \"$s/slow-bin/head\"; "
                + "chmod +x \"$s/slow-bin/head\"; "
                + "module scan-kinds; printf 'import qs.panels\\nQtObject {}\\n' > \"$s/scan-kinds/target.txt\"; ln -s target.txt \"$s/scan-kinds/Link.qml\"; "
                + "mkfifo \"$s/scan-kinds/Fifo.qml\"; forbidden \"$s/scan-kinds/d1/d2/d3/d4/d5/d6/d7/d8/AtLimit.qml\" Quickshell.Hyprland; "
                + "module scan-deep; forbidden \"$s/scan-deep/d1/d2/d3/d4/d5/d6/d7/d8/d9/Past.qml\" Quickshell.Hyprland; "
                + "module scan-many; for n in $(seq 1 101); do printf 'import QtQuick\\nQtObject {}\\n' > \"$s/scan-many/F$n.qml\"; done",
                [_scratch, String(ModuleRules.maxHeaderBytes)], code => suite._made = code);
        });
        _then("the scan fixtures are made", () => _made !== null, () => {
            assertEqual(_made, 0, "made the scan fixtures");
            host.checkEnvironment = { PATH: _scratch + "/slow-bin:" + Quickshell.env("PATH") };
            host.checkTimeoutMs = 1500;
            host.load([_scratch + "/scan-a", _scratch + "/scan-b"], {});
        });
        _then("the slow scan settles", _settled, () => {
            const scanA = host.statuses.find(status => status.id === "scan-a");
            const scanB = host.statuses.find(status => status.id === "scan-b");
            assertEqual(scanB?.state + " " + scanB?.errors.length, "loaded 0",
                        "a module after one whose scanned files hang: its main checked in time, loaded: " + scanB?.errors.join("; "));
            assertEqual(scanA?.state, "loaded", "… the slow one loads too (its scan is no error)");
            assert(_has(scanA?.warnings, "imports not checked in 3 files"), "… and says its imports were not checked: " + JSON.stringify(scanA?.warnings));
            host.checkEnvironment = ({});
            host.checkTimeoutMs = 5000;
            host.load([_scratch + "/scan-kinds", _scratch + "/scan-deep", _scratch + "/scan-many"], {});
        });
        _then("the scan's limits settle", _settled, () => {
            const kinds = host.statuses.find(status => status.id === "scan-kinds");
            assertEqual(kinds?.state, "loaded", "scan-kinds: a FIFO and a link among its QML files, loaded (nothing hung)");
            assert(_has(kinds?.warnings, "d8/AtLimit.qml imports Quickshell.Hyprland"),
                   "… a file " + ModuleFileRules.scanDepth + " directories deep is scanned: " + JSON.stringify(kinds?.warnings));
            assert(!_has(kinds?.warnings, "qs.panels"), "… a link is not followed");
            assert(!_has(kinds?.warnings, "not checked"), "… links and FIFOs are skipped, not counted as unread");
            const deep = host.statuses.find(status => status.id === "scan-deep");
            assert(!_has(deep?.warnings, "Past.qml"), "scan-deep: a file deeper than that is not read");
            assert(_has(deep?.warnings, "imports not checked in 1 or more files"), "… but counted: " + JSON.stringify(deep?.warnings));
            const many = host.statuses.find(status => status.id === "scan-many");
            assert(_has(many?.warnings, "imports not checked in 2 files"),
                   "scan-many: past " + ModuleFileRules.maxScannedFiles + " files, the rest counted: " + JSON.stringify(many?.warnings));
            host.unload();

            // A2: the programs a module names, looked up and judged. The fixture's bin/ is on
            // the look-up's PATH: a program there is the user's (this checkout), so untrusted
            host.programEnvironment = { PATH: fixtures + "/programs/bin:" + Quickshell.env("PATH") };
            host.load(_dirs(["programs"]), {});
        });
        _then("the programs fixture loads", () => _settled() && _status("programs")?.state === "loaded", () => {
            const status = _status("programs");
            assertEqual(status?.errors.length + " " + status?.warnings.length + " " + JSON.stringify(status?.missingPrograms), "0 0 []",
                        "programs: loaded, an optional program missing is no error: " + status?.errors.join("; "));
            const handle = host.handle("programs");
            suite._programsHandle = handle;
            const programs = handle.programs;
            assert(handle.programsReady, "programsReady: every program it names has a verdict");
            assertEqual(Object.keys(programs).sort().join(","), "h2s-fixture-later-program,h2s-fixture-no-such-program,h2s-fixture-user-program,sh",
                        "programs: the required and the optional ones");
            assert(Object.isFrozen(programs) && Object.isFrozen(programs.sh), "… frozen");
            assertEqual(Object.keys(programs.sh).sort().join(","), "path,reason,trusted", "… each { path, trusted, reason }");
            assert(programs.sh.path.startsWith("/") && programs.sh.path.endsWith("/sh") && typeof programs.sh.trusted === "boolean",
                   "sh: found by its absolute path, judged: " + JSON.stringify(programs.sh));
            assertEqual(JSON.stringify(programs["h2s-fixture-no-such-program"]), "{\"path\":\"\",\"trusted\":false,\"reason\":\"not found\"}",
                        "a missing optional program: path \"\", untrusted, not found");
            const user = programs["h2s-fixture-user-program"];
            assertEqual(user.path, fixtures + "/programs/bin/h2s-fixture-user-program", "a program in a directory the user owns: found, by its path");
            assert(user.trusted === false && user.reason.startsWith("others than root can change"),
                   "… and not trusted, though a lying `stat` is beside it on the PATH searched: " + user.reason);
            assertEqual(programs["h2s-fixture-later-program"].path, "", "a program on no directory of the PATH: not found");

            // Looked up again: on a PATH that has it now
            host.programEnvironment = { PATH: fixtures + "/programs/bin:" + fixtures + "/programs/later:" + Quickshell.env("PATH") };
            suite._recheckedAt = Date.now();
            handle.recheckPrograms();
        });
        _then("a recheck finds the program put on PATH", () => _programsHandle.programs["h2s-fixture-later-program"]?.path !== "", () => {
            assertEqual(_programsHandle.programs["h2s-fixture-later-program"].path, fixtures + "/programs/later/h2s-fixture-later-program",
                        "recheckPrograms(): the program on the new PATH found");
            // A second one at once: kept to one look every 2 s, the verdicts stay meanwhile
            host.programEnvironment = { PATH: fixtures + "/programs/bin:" + Quickshell.env("PATH") };
            _programsHandle.recheckPrograms();
            _programsHandle.recheckPrograms();
            assert(_programsHandle.programs["h2s-fixture-later-program"].path !== "", "… a recheck asked: the verdict known stays until the new one");
        });
        _then("the second recheck answers", () => _programsHandle.programs["h2s-fixture-later-program"]?.path === "", () => {
            const waited = Date.now() - _recheckedAt;
            assert(waited >= 1900, "two rechecks at once: the second not before 2 s after the first (" + waited + " ms)");
            assertEqual(_status("programs")?.state, "loaded", "… the module loaded all along");
            // The machine woke: the host looks again by itself
            host.programEnvironment = { PATH: fixtures + "/programs/later:" + Quickshell.env("PATH") };
            host.forwardResumed();
        });
        _then("a wake looks the programs up again", () => _programsHandle.programs["h2s-fixture-later-program"]?.path !== "", () => {
            assertEqual(_programsHandle.programs["h2s-fixture-user-program"].path, "", "after a wake: what is on PATH now");
            host.unload();
            host.programEnvironment = ({});

            // Module test mode (API 1.10): a module's testPrograms are its programs in test
            // mode only. Off, they are ignored: its required program, a stand-in only, is missing.
            // This host's test mode was fixed (off) by its first load
            host.load(_dirs(["test-programs"]), {});
        });
        _then("test-programs settles with test mode off", () => _settled() && _status("test-programs")?.state !== "pending", () => {
            const status = _expectState("test-programs", "missing-program");
            assertEqual(JSON.stringify(status?.missingPrograms), "[\"h2s-fixture-standin\"]", "test mode off: testPrograms ignored, its stand-in not found");
            assert(_has(status?.errors, "h2s-fixture-standin, which is not on PATH"), "… looked for on PATH: " + status?.errors.join("; "));
            const handle = host.handle("test-programs");
            const programs = handle.programs;
            assert(programs.sh.path !== "" && !programs.sh.path.startsWith(fixtures) && programs.sh.reason !== "test stand-in",
                   "… sh from PATH, judged as usual: " + JSON.stringify(programs.sh));
            assert(!String(programs.pkexec?.path).startsWith(fixtures), "… no stand-in pkexec: " + JSON.stringify(programs.pkexec));
            assertEqual(host.testStandIns.length, 0, "… no stand-in pkexec is allowed to run");
            assertEqual(JSON.stringify(host.testProgramVerdicts), "{}", "… no stand-in verdicts");
            assertEqual(host.describe().testMode, false, "describe(): testMode false");

            // (1.36) The handle does not hand out its host; and the host itself refuses a
            // switch of test mode (a module reaching it some other way)
            assertEqual(handle.host, undefined, "a module's handle has no host on it");
            assert(!Object.keys(handle).some(key => { try { return handle[key] === host; } catch (error) { return false; } }),
                   "… nor under another name");
            const reached = host;
            let threw = false;
            try {
                reached.testMode = true;
            } catch (error) {
                threw = true;
            }
            assert(threw && !host.testMode, "writing testMode through the handle: refused (read-only), still off");
            assertEqual(reached.setTestMode(true), false, "setTestMode(true) after the load: refused");
            assertEqual(reached._testModeLatch.fix(true), false, "… the held value's own fix(): refused too");
            threw = false;
            try {
                reached._testModeLatch.fix = () => true;
                reached._testModeLatch.value = () => true;
            } catch (error) {
                threw = true;
            }
            reached._testModeRevision++;
            assert(!host.testMode && !host.describe().testMode && host.testStandIns.length === 0,
                   "… its functions cannot be replaced, nudging the revision changes nothing: still off");
            assertEqual(host.handle("test-programs").programs.pkexec?.reason === "test stand-in", false, "… its programs still from PATH");

            // A host of its own, its test mode fixed on before its load (as tests-modules.qml)
            host.unload();
            suite._mainHost = host;
            const testHost = _hostComponent.createObject(suite);
            assertEqual(testHost.setTestMode(true), true, "setTestMode(true) before any load: fixed on");
            assertEqual(testHost.setTestMode(false), false, "… once: a second call refused");
            assert(testHost.testMode, "… still on");
            suite.host = testHost;
            host.load(_dirs(["test-programs", "test-programs-links", "test-programs-dir-out"]), {});
        });
        _then("test-programs loads in test mode", () => _settled() && _status("test-programs")?.state === "loaded"
              && _status("test-programs-links")?.state === "loaded" && _status("test-programs-dir-out")?.state === "loaded", () => {
            // A module cannot switch test mode off either: the handle has no host, the host refuses
            assertEqual(host.handle("test-programs").host, undefined, "no host on the handle in test mode either");
            const reachedOn = host;
            let threwOff = false;
            try {
                reachedOn.testMode = false;
            } catch (error) {
                threwOff = true;
            }
            assert(threwOff && host.testMode, "writing testMode through the handle: refused, still on");
            assertEqual(reachedOn.setTestMode(false), false, "setTestMode(false) through the handle: refused");
            assert(host.testMode && host.describe().testMode, "… still on");
            const directory = fixtures + "/test-programs/stand-ins";
            const status = _status("test-programs");
            assertEqual(status?.errors.length + " " + JSON.stringify(status?.missingPrograms), "0 []", "test mode: its required stand-in found, loaded: " + status?.errors.join("; "));
            const handle = host.handle("test-programs");
            const programs = handle.programs;
            assert(handle.programsReady && Object.isFrozen(programs) && Object.isFrozen(programs.pkexec), "programsReady, frozen");
            assertEqual(JSON.stringify(programs["h2s-fixture-standin"]),
                        JSON.stringify({ path: directory + "/h2s-fixture-standin", trusted: true, reason: "test stand-in" }),
                        "a program in testPrograms: its path there, trusted, \"test stand-in\"");
            assertEqual(programs.pkexec.path + " " + programs.pkexec.trusted, directory + "/pkexec true", "… pkexec too");
            assertEqual(JSON.stringify(programs.sh), JSON.stringify({ path: "", trusted: false, reason: "no stand-in" }),
                        "a program testPrograms does not hold: not found — never taken from PATH");
            assertEqual(programs["h2s-fixture-not-executable"].path, "", "a file there that is not executable: not found");
            assertEqual(JSON.stringify(host.testStandIns), JSON.stringify([directory + "/pkexec"]),
                        "testStandIns: its stand-in pkexec, the only one a module may start — no link out of a module among them");
            assertEqual(host.describe().testMode, true, "describe(): testMode true");
            // C2: in test mode the data directories lie below a private temporary home the
            // host made, never in the user's data home
            const runtime = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp";
            assert(host.testHome.startsWith(runtime + "/h2s-module-data."), "test mode: a private temporary home, made with mktemp: " + host.testHome);
            assertEqual(handle.dataDirectory, host.testHome + "/.local/share/h2s-shell/module-data/test-programs",
                        "test mode: module.dataDirectory below it");
            suite._testDataDirectory = handle.dataDirectory;
            assertEqual(_status("test-programs")?.deprecations.length, 0, "a 1.10 module: no test-mode gate in its deprecations");

            // Links: a stand-in, or the stand-ins' directory, that leads out of the module is
            // no stand-in — whatever it leads to
            const links = host.handle("test-programs-links").programs;
            assertEqual(links.pkexec.path, "", "a pkexec that links to /run/wrappers/bin/pkexec: no stand-in: " + JSON.stringify(links.pkexec));
            assertEqual(links["h2s-fixture-usr-pkexec"].path, "", "… one that links to /usr/bin/pkexec: none");
            assertEqual(links["h2s-fixture-link-out"].path, "", "… one that links to an executable outside the module: none");
            assertEqual(links["h2s-fixture-inner"].path, fixtures + "/test-programs-links/stand-ins/h2s-fixture-inner",
                        "… a link to a file inside the module: a stand-in");
            const dirOut = host.handle("test-programs-dir-out").programs;
            assertEqual(dirOut.pkexec.path + dirOut["h2s-fixture-standin"].path, "",
                        "a testPrograms directory that links out of the module: nothing in it is a stand-in, pkexec included");

            suite._exists = null;
            _sh("stat -c '%a' \"$1\" \"$2\"", [_testDataDirectory, host.testHome], (code, output) => suite._exists = output.trim());
        });
        _then("the test data directory's mode is read", () => _exists !== null, () => {
            assertEqual(_exists.split("\n").join(" "), "700 700", "… made 700, in a temporary home of 700");
            suite._exists = null;
            // A recheck in test mode looks at the stand-ins again, not at PATH
            host.programEnvironment = { PATH: fixtures + "/programs/bin:" + Quickshell.env("PATH") };
            host.recheckPrograms("test-programs");
            assert(host.checkingPrograms, "a recheck in test mode: a look is running");
        });
        _then("the recheck in test mode answers", () => !host.checkingPrograms, () => {
            assertEqual(host.handle("test-programs").programs.sh.path, "", "… still not from PATH");
            assertEqual(_status("test-programs")?.state, "loaded", "… loaded all along");
            host.programEnvironment = ({});

            // (1.36) Runs as administrator need the manifest's privileged block: refused
            // before any prompt otherwise, and when argv[0] is not a declared program
            host.load(_dirs(["privileged", "privileged-undeclared"]), {});
        });
        _then("the privileged fixtures load in test mode", () => _settled() && _status("privileged")?.state === "loaded"
              && _status("privileged-undeclared")?.state === "loaded", () => {
            const undeclaredHandle = host.handle("privileged-undeclared");
            const declaredHandle = host.handle("privileged");
            const root = undeclaredHandle.programs["h2s-fixture-root"].path;
            assert(root.startsWith(fixtures + "/privileged-undeclared/stand-ins/") && undeclaredHandle.privileged.available,
                   "the undeclared fixture: its program and its stand-in pkexec found, running as administrator available");
            assertEqual(_status("privileged-undeclared")?.errors.length, 0, "… no error before it asks");
            const declared = host.privilegedDeclaration("privileged", declaredHandle.programs);
            assertEqual(JSON.stringify(declared), JSON.stringify({ problem: "", paths: ["talk", "sh", "dismiss", "refuse"].map(name => declaredHandle.programs[name].path) }),
                        "the declared fixture: allowed, its declared programs' stand-ins (absent has none)");
            assertEqual(host.privilegedDeclaration("privileged-undeclared", undeclaredHandle.programs).problem,
                        "asks for administrator rights; module.json does not declare it (privileged)", "the undeclared one: refused, said");
            const queued = PrivilegedRuns.count;
            suite._privilegedAnswers = {};
            const options = name => ({ what: "Try", timeoutMs: 5000, notifyFailures: false, done: result => suite._privilegedAnswers[name] = result });
            // Through each module's own code (its main): only that may ask
            const undeclaredMain = host.mainObject("privileged-undeclared");
            const declaredMain = host.mainObject("privileged");
            undeclaredMain.tryStart([root, "x"], options("undeclared"));
            undeclaredMain.tryStart([root, "again"], options("undeclared again"));
            declaredMain.tryStart([declaredHandle.programs.pkexec.path, "x"], options("not a declared program"));
            // The declared module's handle used from code that is no module's (this suite): refused
            declaredHandle.privileged.start([declaredHandle.programs.talk.path, "x"], options("from outside"));
            // An acknowledgement that does not say privileged: true (Config.acknowledgedModulesText)
            Config.setAcknowledgedModules({ privileged: { source: "user", address: fixtures + "/privileged", author: "", privileged: false } });
            assertEqual(host.privilegedDeclaration("privileged", declaredHandle.programs).problem,
                        "asks for administrator rights; the user has not approved its declaration", "an acknowledgement without privileged: true: not approved");
            declaredMain.tryStart([declaredHandle.programs.talk.path, "x"], options("not approved"));
            Config.setAcknowledgedModulesText(suite._savedAcknowledged);
            // The old PrivilegedAction, from code the shell's own host cannot trace to a module
            // (this host's fixture): refused, fail closed
            suite._mark = undeclaredHandle.dataDirectory + "/pkexec-ran";
            host.mainObject("privileged-undeclared").tryLegacy(suite._mark, result => suite._privilegedAnswers.legacy = result);
            assertEqual(PrivilegedRuns.count, queued, "nothing queued: no prompt can come");
            assertEqual(Object.keys(suite._privilegedAnswers).filter(name => name !== "legacy").length, 0, "… answered after start() returned");
        });
        _then("the refused runs are answered", () => Object.keys(_privilegedAnswers).length === 6, () => {
            const outside = _privilegedAnswers["from outside"];
            assert(outside.blocked === "undeclared" && outside.error === "a run as administrator from code the shell cannot trace to a module is refused",
                   "a declared module's handle used from outside its code: blocked undeclared: " + JSON.stringify(outside));
            const notApproved = _privilegedAnswers["not approved"];
            assert(notApproved.blocked === "undeclared" && notApproved.error === "asks for administrator rights; the user has not approved its declaration",
                   "a declared program, its declaration not approved: blocked undeclared: " + JSON.stringify(notApproved));
            const legacy = _privilegedAnswers.legacy;
            assert(!legacy.ok && legacy.blocked === "undeclared" && legacy.error === "a run as administrator from code the shell cannot trace to a module is refused",
                   "PrivilegedAction from code traced to no module: blocked undeclared: " + JSON.stringify(legacy));
            const answer = _privilegedAnswers.undeclared;
            assert(!answer.ok && answer.blocked === "undeclared" && !answer.dismissed && !answer.refused && answer.code === -1 && answer.stderr === ""
                   && answer.error === "asks for administrator rights; module.json does not declare it (privileged)",
                   "an undeclared module's run: blocked undeclared, nothing ran: " + JSON.stringify(answer));
            const status = _status("privileged-undeclared");
            assertEqual(JSON.stringify(status?.errors), JSON.stringify(["asks for administrator rights; module.json does not declare it (privileged)"]),
                        "… the reason in its status, once for two runs");
            assertEqual(status?.state, "loaded", "… the module stays loaded");
            const stray = _privilegedAnswers["not a declared program"];
            assert(stray.blocked === "undeclared" && stray.error.includes("privileged.programs does not name it") && stray.error.includes("/pkexec"),
                   "a declared module running a program it did not declare: blocked undeclared, which said: " + JSON.stringify(stray));
            assert(_has(_status("privileged")?.errors, "privileged.programs does not name it"), "… in its status");
            assert(_has(_status("privileged")?.errors, "cannot trace to a module"), "… and the run from outside its code");
            assertEqual(PrivilegedRuns.count, 0, "the queue is empty");
            suite._exists = null;
            _sh("if [ -e \"$1\" ]; then echo ran; else echo never; fi", [_mark], (code, output) => suite._exists = output.trim());
        });
        _then("the stand-in pkexec's mark is looked for", () => _exists !== null, () => {
            assertEqual(_exists, "never", "… the undeclared fixture's stand-in pkexec never ran");
            host.unload();
            const testHost = host;
            suite.host = suite._mainHost;
            testHost.destroy();
            host.programEnvironment = ({});

            // A3: the stores' directory made private at the host's start; a store's file
            // written synchronously, atomically, 600; flushed when destroyed; a huge file
            // refused on read
            host.storeDirectory = _scratch + "/config/h2s_shell/modules";
            host.load(_dirs(["good"]), {});
        });
        _then("the store directory is made", () => _settled() && host._storeDirectoryMade, () => {
            suite._store = _storeComponent.createObject(suite, { moduleId: "storetest", path: host.storeDirectory + "/storetest.json" });
        });
        _then("the store is read (missing: empty)", () => _store?.ready, () => {
            assertEqual(JSON.stringify(_store.data), "{}", "a missing file: an empty store");
            assert(_store.set("token", "secret") && _store.set("n", 2), "set");
            // Destroyed within the second before its timer would write: it writes now
            _store.destroy();
            _store = null;
            suite._exists = null;
            _sh("sleep 0.3; cat \"$1/storetest.json\"; echo; stat -c '%a' \"$1\" \"$1/storetest.json\" \"$2\"", [host.storeDirectory, _scratch + "/config/h2s_shell"],
                (code, output) => suite._exists = output);
        });
        _then("the store's file is read back", () => _exists !== null, () => {
            const lines = _exists.trim().split("\n");
            assertEqual(lines[0], "{\"token\":\"secret\",\"n\":2}", "destroyed right after set(): the value is on disk");
            assertEqual(lines[1], "700", "the stores' directory: 700");
            assertEqual(lines[3], "700", "… and the parent it made: 700");
            suite._exists = null;
            // The chmod 600 is detached: read it a moment later
            _sh("sleep 0.3; stat -c '%a' \"$1/storetest.json\"; head -c 2097152 /dev/zero | tr '\\0' x > \"$1/huge.json\"", [host.storeDirectory], (code, output) => suite._exists = output.trim());
        });
        _then("the file's mode is read", () => _exists !== null, () => {
            assertEqual(_exists, "600", "the store's file: 600");
            suite._store = _storeComponent.createObject(suite, { moduleId: "huge", path: host.storeDirectory + "/huge.json" });
        });
        _then("the huge store is read", () => _store?.ready, () => {
            assertEqual(JSON.stringify(_store.data), "{}", "a 2 MiB store file: refused on read, the store empty");
            assert(_has([_store.refusedReason], "larger than"), "… said why: " + _store.refusedReason);
            _store.set("x", 1);
            _store.flush();
            _store.destroy();
            _store = null;
            suite._exists = null;
            _sh("stat -c %s \"$1/huge.json\"", [host.storeDirectory], (code, output) => suite._exists = output.trim());
        });
        _then("the huge file is untouched", () => _exists !== null, () => {
            assertEqual(_exists, "2097152", "… and never overwritten");
            host.unload();
            host.storeDirectory = "";

            // C2: the data directories, outside test mode — a host of its own, so nothing
            // answered before counts; the parent it has to make is 700 too
            suite._dataHost = _hostComponent.createObject(suite, { dataRoot: _scratch + "/data/h2s-shell/module-data" });
            suite._exists = null;
            _sh("mkdir -p \"$1/data\" && chmod 755 \"$1/data\"", [_scratch], () => {
                suite._dataHost.load(_dirs(["good", "needs-program"]), {});
            });
        });
        _then("the data directory is made", () => _dataHost?.statuses.length > 0 && !_dataHost.statuses.some(status => status.state === "pending"), () => {
            const good = _dataHost.statuses.find(status => status.id === "good");
            assertEqual(good?.state + " " + good?.warnings.length, "loaded 0", "good loaded, no warning");
            assertEqual(_dataHost.handle("good").dataDirectory, _scratch + "/data/h2s-shell/module-data/good",
                        "module.dataDirectory: <dataRoot>/<id>");
            assertEqual(_dataHost.handle("needs-program").dataDirectory, "", "a module that does not load (a program missing): none made");
            assertEqual(_dataHost.describe().dataRoot, _scratch + "/data/h2s-shell/module-data", "describe(): the data root");
            _sh("stat -c '%a' \"$1/data\" \"$1/data/h2s-shell\" \"$1/data/h2s-shell/module-data\" \"$1/data/h2s-shell/module-data/good\"; "
                + "test -e \"$1/data/h2s-shell/module-data/needs-program\" && echo made || echo none",
                [_scratch], (code, output) => suite._exists = output.trim());
        });
        _then("the data directories' modes are read", () => _exists !== null, () => {
            assertEqual(_exists.split("\n").join(" "), "755 700 700 700 none",
                        "the data home left as it was; the parent made 700, the root and good's 700; none for the module not loaded");
            _dataHost.unload();
            _dataHost.destroy();
            // A root that is a link: refused — the module loads with no data directory and a warning
            suite._exists = null;
            _sh("mkdir -p \"$1/elsewhere\" && mkdir -p \"$1/linked/h2s-shell\" && ln -s \"$1/elsewhere\" \"$1/linked/h2s-shell/module-data\"",
                [_scratch], () => {
                suite._dataHost = _hostComponent.createObject(suite, { dataRoot: _scratch + "/linked/h2s-shell/module-data" });
                suite._dataHost.load(_dirs(["good"]), {});
            });
        });
        _then("good loads beside a linked data root", () => _dataHost?.statuses.length > 0 && !_dataHost.statuses.some(status => status.state === "pending"), () => {
            const good = _dataHost.statuses.find(status => status.id === "good");
            assertEqual(good?.state, "loaded", "a data directory that cannot be made: the module loads all the same");
            assertEqual(_dataHost.handle("good").dataDirectory, "", "… module.dataDirectory \"\"");
            assert(_has(good?.warnings, "could not be made private (mode 700)"), "… said in its status: " + JSON.stringify(good?.warnings));
            _sh("ls -A \"$1/elsewhere\"", [_scratch], (code, output) => suite._exists = output.trim());
        });
        _then("the link's target is read", () => _exists !== null, () => {
            assertEqual(_exists, "", "nothing made through the link");
            // Turned off and on again once the link is gone: made this time
            suite._exists = null;
            _sh("rm \"$1/linked/h2s-shell/module-data\"", [_scratch], () => {
                suite._dataHost.setEnabled("good", false);
                suite._exists = "off";
            });
        });
        _then("good is off", () => _exists === "off" && _dataHost.statuses.find(status => status.id === "good")?.state === "disabled", () => {
            suite._exists = null;
            _dataHost.setEnabled("good", true);
        });
        _then("good is on again", () => _dataHost.statuses.find(status => status.id === "good")?.state === "loaded", () => {
            const root = _scratch + "/linked/h2s-shell/module-data";
            assertEqual(_dataHost.handle("good").dataDirectory, root + "/good", "a data directory that failed: made again when the module is turned on");
            assertEqual(_dataHost.statuses.find(status => status.id === "good")?.warnings.length, 0, "… the warning gone");
            // Removed while the shell runs: made again at the next load
            _sh("rm -r \"$1/good\"", [root], () => suite._dataHost.load(_dirs(["good"]), {}));
        });
        _then("good loads again", () => _dataHost.statuses.length > 0 && _dataHost.statuses.every(status => status.state !== "pending") && !_dataHost._makingData, () => {
            _sh("stat -c '%a' \"$1/linked/h2s-shell/module-data/good\"", [_scratch], (code, output) => suite._exists = output.trim());
        });
        _then("the removed directory's mode is read", () => _exists !== null, () => {
            assertEqual(_exists, "700", "a data directory removed since: made again (700) at the next load");
            assertEqual(_dataHost.handle("good").dataDirectory, _scratch + "/linked/h2s-shell/module-data/good", "… and shown");
            // The root changed while a run for the old one was out: its answer is dropped,
            // and the directory made in the new root
            suite._exists = null;
            _dataHost.dataRoot = _scratch + "/first/h2s-shell/module-data";
            // The moment the run for the first root starts, the root changes
            const switchRoot = () => {
                if (!suite._dataHost._makingData)
                    return;
                suite._dataHost._makingDataChanged.disconnect(switchRoot);
                suite._switchedRoot = true;
                suite._dataHost.dataRoot = _scratch + "/second/h2s-shell/module-data";
            };
            suite._switchedRoot = false;
            _dataHost._makingDataChanged.connect(switchRoot);
            _dataHost.load(_dirs(["good"]), {});
        });
        _then("good loads in the second root", () => _switchedRoot && _dataHost.statuses.find(status => status.id === "good")?.state === "loaded" && !_dataHost._makingData, () => {
            assertEqual(_dataHost.handle("good").dataDirectory, _scratch + "/second/h2s-shell/module-data/good", "module.dataDirectory: in the root in use");
            _sh("stat -c '%a' \"$1/second/h2s-shell/module-data/good\"", [_scratch], (code, output) => suite._exists = output.trim());
        });
        _then("the second root's directory is read", () => _exists !== null, () => {
            assertEqual(_exists, "700", "… made there: the late answer for the first root did not count for it");
            _dataHost.unload();
            _dataHost.destroy();
            _dataHost = null;
            _sh("rm -rf \"$1\"", [_scratch], () => {});

            // (API 1.18) A module's API for other modules: the consumer fixture uses the
            // provider's exports. The consumer comes first on the search path: the order is
            // the plan's, not the path's. good comes and goes beside them
            const probeComponent = Qt.createComponent("file://" + fixtures + "/provider/ProviderProbe.qml", Component.PreferSynchronous);
            suite._providerProbe = probeComponent.status === Component.Ready ? probeComponent.createObject(suite) : null;
            _created.push(_providerProbe);
            assert(_providerProbe !== null, "the provider's probe is built (it shares the fixture's singleton)");
            _providerProbe.state.log = [];
            host.load(_dirs(["consumer", "provider", "good"]), {});
        });
        _then("the provider and the consumer load", () => _settled() && _status("consumer")?.state !== "pending", () => {
            const providerStatus = _expectState("provider", "loaded");
            const consumerStatus = _expectState("consumer", "loaded");
            assertEqual((providerStatus?.errors ?? []).concat(consumerStatus?.errors ?? []).length, 0, "uses: no errors on either");
            assertEqual(host._order.filter(id => id !== "good").join(","), "provider,consumer", "the provider is planned before its dependent");
            const providerMain = host.mainObject("provider");
            const consumerMain = host.mainObject("consumer");
            assert(providerMain !== null && consumerMain !== null, "both mains made");
            assertEqual(_providerProbe.state.log.join("|"), "provider up|hello consumer up", "the provider's main came first; the consumer used its export while being built");
            assertEqual(consumerMain.answer, "hello, consumer up", "… and got its answer");
            assertEqual(consumerMain.greeting, "hello from the provider", "a binding in the consumer's main to module.uses.provider.greeting");
            const given = consumerMain.usesAtStart;
            assertEqual(Object.keys(given ?? {}).join(","), "provider", "module.uses holds the modules it uses, nothing else");
            assert(given.provider === providerMain.exports, "module.uses.provider is the provider's exports object");
            assert(given.provider !== providerMain, "… not its main");
            assertEqual(given.provider.secret, undefined, "… nothing of the main through it");
            assert(!("parent" in given.provider), "… and no `parent` to climb to the main");
            assertEqual(given.provider.greeting, "hello from the provider", "… its exported properties are there");
            assert(Object.isFrozen(given), "module.uses is frozen");
            assert(host.handle("consumer").uses === given, "the handle's uses: the same object the main read");
            assertEqual(Object.keys(host.handle("provider").uses).length, 0, "a module that uses nothing: module.uses empty");
            suite._oldExports = providerMain.exports;
            suite._oldUses = given;
            // A page of the consumer, bound to module.uses as its main is
            const page = host.settingsPages.find(entry => entry.module === "consumer" || entry.id === "consumer");
            suite._consumerPage = _contributionComponent.createObject(suite, { host: host, moduleId: "consumer", url: page?.component ?? "" });
            _created.push(_consumerPage);
        });
        _then("the consumer's page is built", () => _consumerPage?.ready, () => {
            assertEqual(_consumerPage.item.greeting, "hello from the provider", "a binding in the consumer's page to module.uses.provider.greeting");
            // Other modules come and go: module.uses stays the same object
            assert(host.setEnabled("good", false), "setEnabled(good, false)");
        });
        _then("good goes", () => _status("good")?.state === "disabled", () => {
            assert(host.handle("consumer").uses === suite._oldUses, "another module turned off: module.uses keeps its identity");
            assert(host.setEnabled("good", true), "setEnabled(good, true)");
        });
        _then("good comes back", () => _status("good")?.state === "loaded", () => {
            assert(host.handle("consumer").uses === suite._oldUses, "another module turned on: module.uses keeps its identity");
            _providerProbe.state.log = [];
            // The provider turned off: the consumer's main and page go first, reading module.uses
            // as they go, then the provider
            assert(host.setEnabled("provider", false), "setEnabled(provider, false)");
        });
        _then("the consumer follows the provider off", () => _status("consumer")?.state === "missing-module" && _status("provider")?.state === "disabled"
              && _providerProbe.state.log.includes("provider gone"), () => {
            const consumerStatus = _status("consumer");
            assert(_has(consumerStatus?.errors, "needs module provider 1.1: turned off"), "missing-module, with the reason: " + consumerStatus?.errors.join("; "));
            assertEqual(host.mainObject("consumer"), null, "the consumer's main destroyed");
            assertEqual(host.handle("consumer").active, false, "… its handle inactive");
            assert(host.handle("consumer").uses === suite._oldUses, "… its module.uses unchanged while it is off (what its main and views had)");
            const log = _providerProbe.state.log;
            assertEqual(log.slice().sort().join("|"), ["hello consumer gone: same uses, hello from the provider", "hello page gone: hello from the provider",
                        "provider gone"].sort().join("|"), "the consumer's main and page went reading module.uses as it was: " + log.join("|"));
            assertEqual(log[log.length - 1], "provider gone", "… both before the provider's main");
            assert(!_consumerPage.ready, "the page shows nothing while the consumer is off");
            _providerProbe.state.log = [];
            assert(host.setEnabled("provider", true), "setEnabled(provider, true)");
        });
        _then("the provider comes back, then the consumer and its page", () => _status("consumer")?.state === "loaded" && _consumerPage.ready, () => {
            _expectState("provider", "loaded");
            const consumerMain = host.mainObject("consumer");
            assert(consumerMain?.usesAtStart?.provider === host.mainObject("provider")?.exports, "the new consumer main got the new provider main's exports");
            assert(consumerMain?.usesAtStart?.provider !== suite._oldExports, "… not the old object");
            assert(host.handle("consumer").uses !== suite._oldUses, "module.uses is a new object, set before the new main was made");
            assertEqual(_providerProbe.state.log.join("|"), "provider up|hello consumer up", "the provider first, then the consumer");
            assertEqual(_consumerPage.item.greeting, "hello from the provider", "the page again, bound to the new object");
            // The provider turned off and on in one turn of the event loop: the consumer's going
            // main still reads the old provider's object, and no new main of either comes
            // before the old one of the same module is gone
            _providerProbe.state.log = [];
            host.setEnabled("provider", false);
            host.setEnabled("provider", true);
        });
        _then("the provider off and on in one turn settles", () => _status("consumer")?.state === "loaded" && _consumerPage.ready
              && _providerProbe.state.log.includes("hello consumer up"), () => {
            const log = _providerProbe.state.log;
            const consumerGone = log.indexOf("hello consumer gone: same uses, hello from the provider");
            assert(consumerGone >= 0, "off and on in one turn: the consumer's going main read module.uses as it was: " + log.join("|"));
            assert(consumerGone < log.indexOf("provider gone") && log.indexOf("provider gone") < log.indexOf("provider up")
                   && log.indexOf("provider up") < log.indexOf("hello consumer up"),
                   "… the old consumer main, then the old provider main went before the new provider main, then the new consumer main: " + log.join("|"));
            assertEqual(log.filter(line => line === "provider up").length + " " + log.filter(line => line === "provider gone").length, "1 1",
                        "… one provider main went, one came");
            assert(host.mainObject("consumer")?.usesAtStart?.provider === host.mainObject("provider")?.exports, "… the new consumer main has the new provider's exports");
            // A dependent's main destroyed by something other than the host: its provider is
            // not kept waiting for it
            _providerProbe.state.log = [];
            host.mainObject("consumer").destroy();
        });
        _then("the consumer's main is destroyed from outside", () => _providerProbe.state.log.some(line => line.startsWith("hello consumer gone")), () => {
            _providerProbe.state.log = [];
            host.setEnabled("provider", false);
        });
        _then("the provider goes all the same", () => _status("provider")?.state === "disabled" && _providerProbe.state.log.includes("provider gone"), () => {
            assertEqual(host._going.length, 0, "a dependent's main destroyed from outside: nothing left waiting");
            _providerProbe.state.log = [];
            host.setEnabled("provider", true);
        });
        _then("the provider and the consumer come back", () => _status("consumer")?.state === "loaded" && _consumerPage.ready
              && _providerProbe.state.log.includes("hello consumer up"), () => {
            assertEqual(_providerProbe.state.log.join("|"), "provider up|hello consumer up", "… a new consumer main made after the provider's");
            _providerProbe.state.log = [];
            // A reload of the modules rebuilds everything in the same order
            host.load(_dirs(["consumer", "provider"]), {});
        });
        _then("the reload settles", () => _settled() && _status("consumer")?.state === "loaded" && _consumerPage.ready && _providerProbe.state.log.length >= 5, () => {
            const log = _providerProbe.state.log;
            assertEqual(log.slice(0, 3).sort().join("|"), ["hello consumer gone: same uses, hello from the provider", "hello page gone: hello from the provider",
                        "provider gone"].sort().join("|"), "a reload: the consumer's main and page went reading module.uses as it was: " + log.join("|"));
            assertEqual(log.slice(2).join("|"), "provider gone|provider up|hello consumer up",
                        "… before the provider's main; then the provider's made before the consumer's");
            _consumerPage.destroy();
            suite._consumerPage = null;
            // The shell reloading destroys the whole host: dependents still go first
            suite._mainHost = host;
            suite.host = _hostComponent.createObject(suite);
            host.load(_dirs(["consumer", "provider"]), {});
        });
        _then("a second host loads both", () => _settled() && _status("consumer")?.state === "loaded", () => {
            _providerProbe.state.log = [];
            const doomed = host;
            suite.host = suite._mainHost;
            doomed.destroy();
        });
        _then("the destroyed host's mains are gone", () => _providerProbe.state.log.includes("provider gone"), () => {
            assertEqual(_providerProbe.state.log.join("|"), "hello consumer gone: same uses, hello from the provider|provider gone",
                        "the host destroyed: the consumer's main went first, reading module.uses as it was");
            // A provider that declares exports and whose main gives none: known only once its
            // main is made, in the same pass that would make the consumer's
            host.load(_dirs(["consumer", "provider-no-exports"]), {});
        });
        _then("the provider without an exports object settles", () => _settled() && _status("consumer")?.state !== "pending", () => {
            _expectState("provider-no-exports", "loaded");
            assert(_has(_status("provider-no-exports")?.errors, "exports: "), "the provider says why it gives nothing: " + _status("provider-no-exports")?.errors.join("; "));
            const consumerStatus = _expectState("consumer", "missing-module");
            assert(_has(consumerStatus?.errors, "needs module provider 1.1: gives no exports object"), "… the consumer, missing-module: " + consumerStatus?.errors.join("; "));
            assertEqual(host.mainObject("consumer"), null, "… no consumer main");
            // A provider that offers its own handle: refused
            host.load(_dirs(["consumer", "provider-exports-handle"]), {});
        });
        _then("the provider exporting its handle settles", () => _settled() && _status("consumer")?.state !== "pending", () => {
            _expectState("provider-exports-handle", "loaded");
            assert(_has(_status("provider-exports-handle")?.errors, "exports: its main's `exports` is the shell's"),
                   "a handle as exports: refused, said in the provider's status: " + _status("provider-exports-handle")?.errors.join("; "));
            const consumerStatus = _expectState("consumer", "missing-module");
            assert(_has(consumerStatus?.errors, "needs module provider 1.1: gives no exports object"), "… the consumer, missing-module: " + consumerStatus?.errors.join("; "));
            assertEqual(host.mainObject("consumer"), null, "… no consumer main");
            // A provider whose main fails, in the same pass
            host.load(_dirs(["consumer", "provider-failing-main"]), {});
        });
        _then("the provider with a failing main settles", () => _settled() && _status("consumer")?.state !== "pending", () => {
            _expectState("provider-failing-main", "failed");
            const consumerStatus = _expectState("consumer", "missing-module");
            assert(_has(consumerStatus?.errors, "needs module provider 1.1: failed"), "… the consumer, missing-module: " + consumerStatus?.errors.join("; "));
            assertEqual(host.mainObject("consumer"), null, "… no consumer main");
            // Without the provider installed
            host.load(_dirs(["consumer"]), {});
        });
        _then("the consumer alone settles", () => _settled() && _status("consumer")?.state !== "pending", () => {
            const consumerStatus = _expectState("consumer", "missing-module");
            assert(_has(consumerStatus?.errors, "needs module provider 1.1: not installed"), "a provider not installed: said: " + consumerStatus?.errors.join("; "));
            assertEqual(host.mainObject("consumer"), null, "… no main");
            // A dependent with no main, only a view: the provider's main waits for the view too
            host.load(_dirs(["consumer-views", "provider"]), {});
        });
        _then("the views-only consumer loads", () => _settled() && _status("consumer-views")?.state === "loaded", () => {
            const page = host.settingsPages.find(entry => entry.module === "consumer-views" || entry.id === "consumer-views");
            suite._consumerPage = _contributionComponent.createObject(suite, { host: host, moduleId: "consumer-views", url: page?.component ?? "" });
            _created.push(_consumerPage);
        });
        _then("the views-only consumer's page is built", () => _consumerPage?.ready, () => {
            assertEqual(_consumerPage.item.greeting, "hello from the provider", "a page of a module without a main, bound to module.uses");
            _providerProbe.state.log = [];
            host.setEnabled("provider", false);
        });
        _then("the provider goes after the views-only consumer's page", () => _providerProbe.state.log.includes("provider gone"), () => {
            assertEqual(_providerProbe.state.log.join("|"), "hello views page gone: hello from the provider|provider gone",
                        "a dependent with only views: its page went reading module.uses, before the provider's main");
            host.setEnabled("provider", true);
        });
        _then("the views-only consumer is back", () => _status("consumer-views")?.state === "loaded" && _consumerPage.ready, () => {
            _consumerPage.destroy();
            suite._consumerPage = null;
            // (API 1.30) A soft use: the consumer loads without the provider, module.uses.provider null
            host.load(_dirs(["consumer-soft"]), {});
        });
        _then("the soft consumer alone settles", () => _settled() && _status("consumer-soft")?.state !== "pending", () => {
            const status = _expectState("consumer-soft", "loaded");
            assertEqual((status?.errors ?? []).length + (status?.warnings ?? []).length, 0, "soft uses not installed: loaded, nothing said: "
                        + (status?.errors ?? []).concat(status?.warnings ?? []).join("; "));
            const main = host.mainObject("consumer-soft");
            assertEqual(JSON.stringify(main?.usesAtStart), JSON.stringify({ provider: null, absent: null }), "module.uses: each soft use null without its provider");
            assertEqual(main?.answer, "no provider", "… the main saw null while it was built");
            _providerProbe.state.log = [];
            host.load(_dirs(["consumer-soft", "provider"]), {});
        });
        _then("the soft consumer with its provider settles", () => _settled() && _status("consumer-soft")?.state === "loaded" && host.mainObject("consumer-soft")?.answer !== "no provider", () => {
            assertEqual(host._order.join(","), "provider,consumer-soft", "a soft provider there: planned before its dependent");
            const main = host.mainObject("consumer-soft");
            assert(main.usesAtStart.provider === host.mainObject("provider")?.exports && main.usesAtStart.absent === null,
                   "module.uses.provider: the provider's exports object; the one not installed still null");
            assertEqual(_providerProbe.state.log.join("|"), "provider up|hello soft up", "the provider's main first, then the soft consumer's");
            suite._softMain = main;
            _providerProbe.state.log = [];
            host.setEnabled("provider", false);
        });
        _then("the soft consumer restarts without the provider", () => _status("consumer-soft")?.state === "loaded" && host.mainObject("consumer-soft") !== null
              && host.mainObject("consumer-soft") !== suite._softMain && _providerProbe.state.log.includes("provider gone"), () => {
            assertEqual(_providerProbe.state.log.join("|"), "hello soft gone: same uses|provider gone",
                        "the provider turned off: the soft consumer's main went first, reading module.uses as it was, then the provider's");
            assertEqual(host.mainObject("consumer-soft").usesAtStart.provider, null, "… a new main, module.uses.provider null");
            assertEqual(_status("consumer-soft").errors.length, 0, "… loaded, no error");
            suite._softMain = host.mainObject("consumer-soft");
            _providerProbe.state.log = [];
            host.setEnabled("provider", true);
        });
        _then("the soft consumer restarts with the provider back", () => _status("consumer-soft")?.state === "loaded"
              && host.mainObject("consumer-soft") !== suite._softMain && host.mainObject("consumer-soft")?.answer === "hello, soft up", () => {
            assertEqual(_providerProbe.state.log.join("|"), "provider up|hello soft up", "the provider back: its main, then a new soft consumer main");
            assert(host.mainObject("consumer-soft").usesAtStart.provider === host.mainObject("provider")?.exports, "… given the new provider's object");
            suite._softMain = null;
            // A provider there whose main gives no exports object: loaded without it, noted
            host.load(_dirs(["consumer-soft", "provider-no-exports"]), {});
        });
        _then("the soft consumer beside a provider without exports settles", () => _settled() && _status("consumer-soft")?.state !== "pending", () => {
            const status = _expectState("consumer-soft", "loaded");
            assert(_has(status?.warnings, "can use module provider 1.1: gives no exports object") && status.errors.length === 0,
                   "… noted as a warning, no error: " + status?.warnings.join("; "));
            assertEqual(host.mainObject("consumer-soft")?.usesAtStart?.provider, null, "… module.uses.provider null");
            host.load(_dirs(["consumer-soft", "provider-failing-main"]), {});
        });
        _then("the soft consumer beside a failing provider settles", () => _settled() && _status("consumer-soft")?.state !== "pending", () => {
            _expectState("provider-failing-main", "failed");
            const status = _expectState("consumer-soft", "loaded");
            assertEqual(status?.errors.length, 0, "a soft provider whose main failed: loaded, no error");
            assertEqual(host.mainObject("consumer-soft")?.usesAtStart?.provider, null, "… module.uses.provider null");
            // A chain: zmid soft-uses the provider; ztop needs zmid, ztop-soft can use it. A
            // restarting zmid takes the mains using it along, and they go before it
            host.load(_dirs(["ztop", "ztop-soft", "zmid", "provider"]), {});
        });
        _then("the chain loads", () => _settled() && _chainMains(["provider", "zmid", "ztop", "ztop-soft"]), () => {
            assertEqual(host._order.join(","), "provider,zmid,ztop,ztop-soft", "the chain: providers first");
            _watchChain(["zmid", "ztop", "ztop-soft"]);
            host.setEnabled("provider", false);
        });
        _then("the chain restarts without the provider", () => _settled() && _chainRestarted(["zmid", "ztop", "ztop-soft"]), () => {
            assertEqual(_chainLog.join("|"), "soft top gone, mid ping=pong|top gone, mid ping=pong|mid gone",
                        "the provider off: the mains using zmid went first, still reaching it, then zmid's");
            _watchChain(["zmid", "ztop", "ztop-soft"]);
            host.setEnabled("provider", true);
        });
        _then("the chain restarts with the provider back", () => _settled() && _chainRestarted(["zmid", "ztop", "ztop-soft"]) && host.mainObject("provider") !== null, () => {
            assertEqual(_chainLog.join("|"), "soft top gone, mid ping=pong|top gone, mid ping=pong|mid gone",
                        "the provider back: the mains using zmid went first, still reaching it, then zmid's");
            assert(host.mainObject("ztop").module.uses.zmid === host.mainObject("zmid").exports, "… ztop given the new zmid's object");
            // Soft all the way: provider ← zmid ← ztop-soft
            host.load(_dirs(["ztop-soft", "zmid", "provider"]), {});
        });
        _then("the soft chain loads", () => _settled() && _chainMains(["provider", "zmid", "ztop-soft"]), () => {
            _watchChain(["zmid", "ztop-soft"]);
            host.setEnabled("provider", false);
        });
        _then("the soft chain restarts without the provider", () => _settled() && _chainRestarted(["zmid", "ztop-soft"]), () => {
            assertEqual(_chainLog.join("|"), "soft top gone, mid ping=pong|mid gone", "a soft chain: its top went first, still reaching zmid");
            assert(host.mainObject("ztop-soft").module.uses.zmid === host.mainObject("zmid").exports, "… given the new zmid's object");
            host.setEnabled("provider", true);
        });
        _then("the soft chain is back", () => _settled() && host.mainObject("provider") !== null && host.mainObject("ztop-soft") !== null, () => {
            // A soft dependent never given zmid (it asks for a major zmid does not have)
            host.load(_dirs(["ztop-unfit", "zmid", "provider"]), {});
        });
        _then("the unfitting top loads", () => _settled() && _chainMains(["provider", "zmid", "ztop-unfit"]), () => {
            const status = _expectState("ztop-unfit", "loaded");
            assert(_has(status?.warnings, "can use module zmid 2.0: has 1.0"), "a soft use that does not fit: a warning: " + status?.warnings.join("; "));
            assertEqual(host.mainObject("ztop-unfit").module.uses.zmid, null, "… module.uses.zmid null");
            _watchChain(["zmid", "ztop-unfit"]);
            host.setEnabled("provider", false);
        });
        _then("zmid restarts without the provider", () => _settled() && _chainRestarted(["zmid"]), () => {
            assertEqual(_chainLog.join("|"), "mid gone", "zmid restarted alone: a soft dependent it never gave anything to stays");
            assert(host.mainObject("ztop-unfit") === _chainWatched["ztop-unfit"] && _status("ztop-unfit")?.state === "loaded", "… the same main, loaded");
            host.setEnabled("provider", true);
        });
        _then("zmid is back with the provider", () => _settled() && host.mainObject("provider") !== null && _chainMains(["zmid", "ztop-unfit"]), () => {
            assert(host.mainObject("ztop-unfit") === _chainWatched["ztop-unfit"], "… and when it comes back the unfitting top still keeps its main");
            // A soft dependent whose main something else deleted, restarting alone (its
            // provider made in a pass where nothing else goes): not left pending
            host.load(_dirs(["consumer-soft", "provider"]), {});
        });
        _then("the soft consumer and the provider load", () => _settled() && _status("consumer-soft")?.state === "loaded" && host.mainObject("consumer-soft")?.answer === "hello, soft up", () => {
            host.setEnabled("provider", false);
        });
        _then("the soft consumer runs without the provider", () => _settled() && _status("consumer-soft")?.state === "loaded" && host.mainObject("consumer-soft")?.answer === "no provider", () => {
            host.mainObject("consumer-soft").destroy();
        });
        _then("the soft consumer's main is destroyed from outside", () => host._records.some(record => record.manifest.id === "consumer-soft" && record.mainDeleted), () => {
            // The provider turned on in one pass (setEnabled applies twice: the second pass
            // would make the consumer's main whatever the first left waiting); the consumer
            // restarts, its old main already gone: nothing goes, so nothing would apply it
            // again unless the host does when it finds that main gone
            Config.disabledModules = host._plainList(Config.disabledModules).filter(id => id !== "provider");
        });
        _then("the soft consumer restarts with the provider", () => _status("consumer-soft")?.state === "loaded" && host.mainObject("consumer-soft")?.answer === "hello, soft up", () => {
            assertEqual(host._going.length, 0, "a restarting main deleted from outside: nothing left waiting");
            host.unload();
        }, 3000);
        _trustSteps();
        _clock.start();
    }

    // ---- Sources and confirmations (notes/plans/modules-management.md §3, §5) ----
    //
    // A host that confirms, its places in the test's own directory: a development path, a user
    // root (a folder, a folder turned off, a link to a privileged module), a built-in root
    // with builtin.json. Found by the launcher's own search (rediscover), read by the source
    // check: the first start acknowledges what is on; a module put there later starts
    // unconfirmed; a changed author or a first privileged declaration holds one for approval;
    // confirm() turns it on; nothing acts while locked; a late search loses; safe mode left in
    // place; the modules on written and read back.

    readonly property string _trustRoot: _scratch + "/trust"
    property var _trustHost: null
    property var _trustReader: null
    property bool _trustWritten: false
    property var _trustAll: []
    // A file's text as last read, and whether a read is under way (a step's condition)
    property var _fileTexts: ({})
    property var _fileReading: ({})

    function _fileReads(path, expected) {
        if (!_fileReading[path]) {
            _fileReading[path] = true;
            _sh("cat \"$1\" 2>/dev/null || echo '(none)'", [path], (code, output) => {
                suite._fileTexts[path] = output.trim();
                suite._fileReading[path] = false;
            });
        }
        return _fileTexts[path] === expected;
    }

    // Writes files ({ path below the root: text }) and links ([[link, target]]) under the root
    function _writeTree(files, links) {
        suite._trustWritten = false;
        const argv = [_trustRoot];
        for (const path of Object.keys(files))
            argv.push("f", path, files[path]);
        for (const link of links ?? [])
            argv.push("l", link[0], link[1]);
        _sh("T=$1; shift; while [ $# -ge 3 ]; do mkdir -p \"$(dirname \"$T/$2\")\"; "
            + "if [ \"$1\" = f ]; then printf '%s\\n' \"$3\" > \"$T/$2\"; else ln -sfn \"$T/$3\" \"$T/$2\"; fi; shift 3; done", argv,
            () => suite._trustWritten = true);
    }

    function _manifest(id, extra) {
        return JSON.stringify(Object.assign({ id: id, name: id.charAt(0).toUpperCase() + id.slice(1), version: "1.0.0", api: "1.36" }, extra ?? {}));
    }

    function _trust(id) {
        return _trustHost?.status(id) ?? null;
    }

    function _trustSettled() {
        return _trustHost !== null && _trustHost.settled && !_trustHost.checkingPrograms && !_trustHost.discovering;
    }

    function _trustSteps() {
        const user = "data/h2s-shell/modules/";
        const privileged = { optionalPrograms: ["sh"], privileged: { why: "Test", programs: ["sh"] } };
        _then("the main host is done", () => true, () => {
            _writeTree({
                [user + "old/module.json"]: _manifest("old", { author: "Anna" }),
                [user + "off/module.json"]: _manifest("off"),
                ["src/linked/module.json"]: _manifest("linked", privileged),
                ["builtin/shipped/module.json"]: _manifest("shipped"),
                ["builtin/shipped-off/module.json"]: _manifest("shipped-off"),
                ["builtin/builtin.json"]: JSON.stringify({ off: ["shipped-off"] }),
                ["dev/devmod/module.json"]: _manifest("devmod", { main: "Main.qml" }),
                ["dev/devmod/Main.qml"]: "import QtQuick\nQtObject {}"
            }, [[user + "linked", "src/linked"]]);
        });
        _then("the trust tree is written", () => _trustWritten, () => {
            const places = ModuleInstallRules.sourcePlaces({ dataHome: _trustRoot + "/data", modulePath: _trustRoot + "/dev", moduleDataDirs: "",
                                                             builtin: _trustRoot + "/builtin" });
            suite._trustHost = _hostComponent.createObject(suite, {
                confirmations: true, sourcePlaces: places, modulesOnFile: _trustRoot + "/modules-on",
                discoveryCommand: ["bash", Quickshell.shellDir + "/scripts/launch.sh", "--discover-modules"],
                discoveryEnvironment: { XDG_DATA_HOME: _trustRoot + "/data", H2S_SHELL_MODULE_PATH: _trustRoot + "/dev",
                                        H2S_SHELL_MODULE_DATA_DIRS: "", H2S_SHELL_BUILTIN_MODULES: _trustRoot + "/builtin" }
            });
            _created.push(_trustHost);
            // Never written: the first start's baseline
            Config.setAcknowledgedModules(undefined);
            Config.disabledModules = ["off"];
            Config.enabledModules = [];
            // No baseline from a list no search answered with, nor from an empty one
            _trustHost.load([], { searched: true });
        });
        _then("an empty searched list settles", () => _trustSettled(), () => {
            _trustHost.load([_trustRoot + "/dev/devmod", _trustRoot + "/" + user + "old"], {});
        });
        _then("a list no search answered with loads", () => _trustSettled() && _fileReads(_trustRoot + "/modules-on", "devmod\nold"), () => {
            assertEqual(_trustHost.acknowledgements, undefined, "an empty searched list, then a list not searched: no acknowledgement written");
            assertEqual(_trust("old")?.state, "loaded", "… what is found counts as acknowledged meanwhile");
            assertEqual(_trustHost.rediscover(), "", "the launcher's search started");
        });
        _then("the first start settles and writes its baseline", () => _trustSettled() && _trustHost.acknowledgements !== undefined
              && _trust("off")?.state === "unconfirmed" && _trust("old")?.state === "loaded", () => {
            assertEqual(_trustHost.statuses.map(status => status.id).join(" "), "devmod linked off old shipped shipped-off",
                        "the launcher's search, loaded in place: development path, user root, built-in root");
            suite._trustAll = _trustHost.directories.slice();
            const label = id => _trust(id)?.source + " | " + _trust(id)?.sourceLabel;
            assertEqual(label("devmod"), "developer | Development path", "a module on the development path: developer");
            assertEqual(label("old"), "user | Your copy", "a folder placed in the user root: user, \"Your copy\"");
            assertEqual(label("linked"), "user | Your link → " + _trust("linked").directory, "a link placed there: user, where it leads");
            assertEqual(label("shipped"), "builtin | Built-in", "in the built-in root: builtin");
            assert(_trust("old")?.entry.endsWith("/old") && _trust("linked")?.entry.endsWith("/linked") && _trust("linked").entry !== _trust("linked").directory,
                   "the status's entry: its place in the user root (a link's own path, not its target)");
            assertEqual(_trust("shipped")?.entry + "|" + _trust("devmod")?.entry, "|", "… none outside it");
            assertEqual(_trust("shipped")?.state, "loaded", "… loaded, never asked about");
            assertEqual(_trust("shipped-off")?.state + " " + _trust("shipped-off")?.enabled, "disabled false", "listed off by builtin.json: off");
            const list = _trustHost.acknowledgements;
            assertEqual(Object.keys(list).sort().join(" "), "linked old", "the baseline: the hand-placed modules that were on, acknowledged as found");
            assertEqual(JSON.stringify(list.linked), JSON.stringify({ source: "user", address: _trust("linked").directory, author: "", privileged: true }),
                        "… the link with its privileged declaration consented (it stays on, with no prompt)");
            assertEqual(list.old.author, "Anna", "… with its author");
            assertEqual(_trust("linked")?.state, "loaded", "the privileged link stays loaded");
            assertEqual(_trustHost.privilegedDeclaration("linked", _trustHost.handle("linked").programs).problem, "",
                        "… and its runs as administrator are approved");
            const off = _trust("off");
            assertEqual(off?.state + " " + JSON.stringify(off?.confirmation), "unconfirmed [\"new\"]",
                        "one that was off at the first start: unconfirmed once the list is written");
            assertEqual(_trustHost.setEnabled("off", true), false, "setEnabled refuses a module that waits for confirmation");
            assertEqual(_trustHost.enableProblem("off"), "Off is new and not part of h2s-shell: confirm it first (modules confirm off <directory>)", "… and says why");
            assert(_trustHost.setEnabled("shipped-off", true), "a built-in module that starts off: turned on");
            assertEqual(_trustHost._plainList(Config.enabledModules).join(" "), "shipped-off", "… remembered in enabledModules");
        });
        _then("the built-in module turned on loads", () => _trust("shipped-off")?.state === "loaded", () => {
            assert(_trustHost.setEnabled("shipped-off", false), "… and off again");
            assertEqual(_trustHost._plainList(Config.enabledModules).length, 0, "… gone from enabledModules");
            assertEqual(_trustHost.confirm("off"), "", "confirm: done");
            assertEqual(_trustHost.acknowledgements.off?.source, "user", "… its acknowledgement written");
        });
        _then("confirming turns it on", () => _trust("off")?.state === "loaded" && _trust("shipped-off")?.state === "disabled", () => {
            assert(!_trustHost._plainList(Config.disabledModules).includes("off"), "confirm took it off the disabled list");
        });
        _then("the modules on are written", () => _fileReads(_trustRoot + "/modules-on", "devmod\nlinked\noff\nold\nshipped"), () => {
            // A module put there later, an author changed, a main changed in place
            _writeTree({
                [user + "fresh/module.json"]: _manifest("fresh"),
                [user + "old/module.json"]: _manifest("old", { author: "Bob" }),
                ["dev/devmod/Main.qml"]: "import QtQuick\nQtObject { property int changed: 1 }"
            });
        });
        _then("the changes are written", () => _trustWritten, () => {
            assertEqual(_trustHost.rediscover(), "", "searched again without a restart");
        });
        _then("the search again loads what changed", () => _trustSettled() && _trust("fresh")?.state === "unconfirmed" && _trust("old")?.state === "approval", () => {
            assertEqual(JSON.stringify(_trust("fresh").confirmation), "[\"new\"]", "a module put on disk after the first start: unconfirmed, new");
            assertEqual(JSON.stringify(_trust("old").confirmation), "[\"author\"]", "a hand-placed module whose author changed: held for approval");
            assertEqual(_trustHost.enableProblem("old"), "Old now names another author: approve it first (modules confirm old <directory>)", "… said");
            assertEqual(JSON.stringify(_trustHost.restartNeeded), "[\"Devmod\"]", "a main changed in place since the engine built it: a restart needed");
            assertEqual(JSON.stringify(_trustHost.describe().restartNeeded), "[\"Devmod\"]", "… in modules list");
            assertEqual(_trust("devmod")?.state, "loaded", "… it keeps running");
            _trustHost.locked = true;
            assertEqual(_trustHost.confirm("fresh"), "Refused while the session is locked", "locked: confirm refused");
            assertEqual(_trustHost.rediscover(), "Refused while the session is locked", "locked: the search refused");
            _trustHost.locked = false;
            assertEqual(_trustHost.confirm("devmod"), "devmod needs no confirmation", "confirm on a module that needs none: said, nothing done");
            assertEqual(_trustHost.confirm("nope"), "No module \"nope\"", "confirm on no module: said");
            assertEqual(_trustHost.confirm("fresh", "/elsewhere/fresh"), "The module changed: fresh is now " + _trust("fresh").directory,
                        "confirm for another directory than the id's now: refused");
            assertEqual(_trust("fresh")?.state, "unconfirmed", "… nothing done");
            assertEqual(_trustHost.confirm("fresh") + _trustHost.confirm("old"), "", "confirm both");
        });
        _then("both load once confirmed", () => _trust("fresh")?.state === "loaded" && _trust("old")?.state === "loaded", () => {
            assertEqual(_trustHost.acknowledgements.old.author, "Bob", "the approval took the new author");
            _writeTree({ [user + "fresh/module.json"]: _manifest("fresh", privileged) });
        });
        _then("fresh now declares privileged", () => _trustWritten, () => _trustHost.rediscover());
        _then("a first privileged declaration is held", () => _trustSettled() && _trust("fresh")?.state === "approval", () => {
            assertEqual(JSON.stringify(_trust("fresh").confirmation), "[\"privileged\"]", "a hand-placed module that starts declaring administrator actions: approval");
            assertEqual(_trustHost.privilegedDeclaration("fresh", _trustHost.handle("fresh").programs).problem,
                        "asks for administrator rights; the user has not approved its declaration", "… its runs as administrator refused");
            // A search started before a load answers for nothing
            _trustHost.discoveryCommand = ["sh", "-c", "sleep 0.3; printf %s \"$1\"; : > \"$2\"", "sh", _trustAll.join(":"), _trustRoot + "/searched"];
            assertEqual(_trustHost.rediscover(), "", "a slow search started");
            _trustHost.load([_trustAll[0]], {});
        });
        _then("the slow search has answered", () => _fileReads(_trustRoot + "/searched", ""), () => {
            assertEqual(_trustHost.directories.join(":"), _trustAll[0], "… its answer lost to the load after it");
        });
        _then("the modules on follow", () => _trustSettled() && _fileReads(_trustRoot + "/modules-on", "devmod"), () => {
            assertEqual(_trustHost.loadWithoutSafeMode(), "Not in safe mode", "out of safe mode: nothing to leave");
            _trustHost.discoveryCommand = ["bash", Quickshell.shellDir + "/scripts/launch.sh", "--discover-modules"];
            _trustHost.load(_trustAll, { safeMode: true });
        });
        _then("safe mode settles", () => _trustSettled() && _trust("devmod")?.state === "safe-mode", () => {
            assertEqual(_trustHost.loadWithoutSafeMode(), "", "load without safe mode: the search started");
        });
        _then("the modules load out of safe mode, in place", () => _trustSettled() && !_trustHost.safeMode && _trust("old")?.state === "loaded", () => {
            assertEqual(_trust("devmod")?.state + " " + _trust("fresh")?.state, "loaded approval", "… each in its own state");
            suite._fileTexts = ({});
        });
        _then("the modules on are written again", () => _fileReads(_trustRoot + "/modules-on", "devmod\nlinked\noff\nold\nshipped"), () => {
            suite._trustReader = _hostComponent.createObject(suite, { modulesOnFile: _trustRoot + "/modules-on" });
            _created.push(_trustReader);
            _trustReader.load([], {});
        });
        _then("a new host reads the modules on in the last run", () => _trustReader.previousModulesOn.length > 0, () => {
            assertEqual(_trustReader.previousModulesOn.join(" "), "devmod linked off old shipped", "previousModulesOn: what the last run wrote");
            assertEqual(JSON.stringify(_trustReader.describe().previousModulesOn), JSON.stringify(_trustReader.previousModulesOn), "… in modules list");
            _trustHost.unload();
            _trustReader.unload();
        });
    }

    property var _providerProbe: null
    // The chain fixtures: what their mains said as they went, and the mains watched
    property var _chainLog: []
    property var _chainWatched: ({})

    function _chainMains(ids) {
        return ids.every(id => _status(id)?.state === "loaded" && host.mainObject(id) !== null);
    }

    function _watchChain(ids) {
        suite._chainLog = [];
        const watched = {};
        for (const id of ids) {
            const main = host.mainObject(id);
            main.report = text => suite._chainLog = suite._chainLog.concat([text]);
            watched[id] = main;
        }
        suite._chainWatched = watched;
    }

    // Each watched main replaced by a new one, loaded
    function _chainRestarted(ids) {
        return _chainMains(ids) && ids.every(id => host.mainObject(id) !== _chainWatched[id]);
    }
    property var _oldExports: null
    property var _oldUses: null
    property var _softMain: null
    property var _consumerPage: null
    property Component _contributionComponent: Component {
        ModuleContribution {}
    }

    property var _goodState: null
    property var _dataHost: null
    property bool _switchedRoot: false
    property string _testDataDirectory: ""
    // The suite's own host while a second one, in test mode, is `host`
    property var _mainHost: null
    property Component _hostComponent: Component {
        ModuleHost {
            logStates: false
        }
    }
    property var _hungSince: 0
    property var _programsHandle: null
    property var _recheckedAt: 0
    property var _store: null
    property Component _storeComponent: Component {
        ModuleStore {
            // The runner's Config is read-only: this store writes, into the test's own directory
            writable: true
        }
    }
    property var _made: null
    property var _exists: null
    // The start counter's file as last read, and whether a read is under way
    property string _counter: ""
    // When the start guard answered (its window armed) and when it cleared, on a monotonic clock
    property real _guardArmedAt: -1
    property real _guardClearedAt: -1
    property ElapsedTimer _monotonic: ElapsedTimer {}
    property Connections _guardWatch: Connections {
        target: suite.host
        function onGuardChanged() {
            const guard = suite.host.guard;
            if (guard === null)
                return;
            if (guard.cleared === true)
                suite._guardClearedAt = Number(suite._monotonic.elapsedMs());
            else
                suite._guardArmedAt = Number(suite._monotonic.elapsedMs());
        }
    }
    property bool _readingCounter: false
    // Whether the counter file reads `expected`: a step's condition, read anew while it waits
    function _counterReads(expected) {
        if (!_readingCounter) {
            _readingCounter = true;
            _sh("cat \"$1/starts\"", [_scratch], (code, output) => {
                suite._counter = output.trim();
                suite._readingCounter = false;
            });
        }
        return _counter === expected;
    }
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
