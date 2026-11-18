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
            assertEqual(JSON.stringify(good?.deprecations ?? null), "[]", "good: on qs.api alone, nothing deprecated");
            assertEqual(good?.version + " " + good?.api + " " + good?.name, "1.2.3 1.12 Good fixture", "good: version, API, name");
            assertEqual(good?.directory, fixtures + "/good", "good: its canonical directory");
            const main = host.mainObject("good");
            assert(main !== null, "good: its main was created");
            assertEqual(main?.goodState.mains, 1, "good: one main, once (the two other spellings did not load it again)");

            // module.log (API 1.12): with a key, once per change of text
            const goodHandle = host.handle("good");
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
            assert(_has(forbidden?.warnings, "imports qs.singletons"), "forbidden-import: loaded, with a warning naming the import");
            assertEqual(forbidden?.errors.length, 0, "forbidden-import: a warning, not an error");
            assert(_has(forbidden?.warnings, "sections/deeper/Deeper.qml imports Quickshell.Hyprland"),
                   "forbidden-import: a QML file in a subdirectory, named nowhere, is scanned too: " + JSON.stringify(forbidden?.warnings));
            assert(_has(forbidden?.deprecations, "qs.components (in sections/Section.qml)"),
                   "… and its deprecated import listed: " + JSON.stringify(forbidden?.deprecations));
            assert(!_has(forbidden?.warnings, "qs.panels"), "… but not one in a hidden directory");

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
            assertEqual(host.handle("good")._logWritten.size, 0, "disabled: its log keys forgotten");
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

            // A module cannot switch test mode: what its handle hands it (`host`) refuses
            const reached = handle.host;
            assert(reached === host, "a module's handle reaches the host");
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

            // A recheck in test mode looks at the stand-ins again, not at PATH
            host.programEnvironment = { PATH: fixtures + "/programs/bin:" + Quickshell.env("PATH") };
            host.recheckPrograms("test-programs");
            assert(host.checkingPrograms, "a recheck in test mode: a look is running");
        });
        _then("the recheck in test mode answers", () => !host.checkingPrograms, () => {
            assertEqual(host.handle("test-programs").programs.sh.path, "", "… still not from PATH");
            assertEqual(_status("test-programs")?.state, "loaded", "… loaded all along");
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
            _sh("rm -rf \"$1\"", [_scratch], () => {});
        });
        _clock.start();
    }

    property var _goodState: null
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
