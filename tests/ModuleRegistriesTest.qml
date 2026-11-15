import QtQuick
import Quickshell
import Quickshell.Io
import qs.api
import qs.components
import qs.singletons

// The core's registries with modules in them (docs/plans/modules.md, M2), on the shell's own
// host (Modules.host) — so after ModulesTest, whose host loads the same fixtures (`after`):
// with no module every registry is the core's list itself; the `good` fixture loaded, its
// widget, popup, presets, settings, popup-mode entry, facts, settings page, handle and slot
// contribution are in; a contribution that does not compile is contained; turning it off
// takes all of it away (and what of it acted stops: the A6 contract), on again brings it back;
// and the reserved ids cover what the core's tree names (IPC targets, widget types, popup
// keys, settings page ids). Asynchronous.
TestCase {
    id: suite
    suiteName: "ModuleRegistries"
    asynchronous: true

    // A suite that must be done first (it loads the same fixtures in a host of its own)
    property var after: null

    readonly property string fixtures: Quickshell.shellDir + "/tests/fixtures/modules"
    property var _steps: []
    property var _savedDisabled: []
    property var _window: null
    property var _slots: ({})
    property var _main: null
    // The module's singleton: it outlives the main
    property var _goodState: null
    property int _ticksAtStop: 0
    property var _grepped: null
    property real _waitUntil: 0

    function _then(description, condition, action, timeoutMs) {
        _steps.push({ description: description, condition: condition, action: action, deadline: timeoutMs ?? 15000 });
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
        Modules.host.unload();
        Config.disabledModules = _savedDisabled;
        for (const name of Object.keys(_slots))
            _slots[name]?.destroy();
        _window?.destroy();
        finish();
    }

    function _settled() {
        const statuses = Modules.host.statuses;
        return statuses.length > 0 && !statuses.some(status => status.state === "pending") && !Modules.host.checkingFiles;
    }

    function _slot(name, context) {
        const slot = Qt.createQmlObject("import QtQuick; import qs.components; ModuleSlot { width: 200 }", suite);
        slot.name = name;
        slot.context = context ?? {};
        _slots[name] = slot;
        return slot;
    }

    function _has(list, fragment) {
        return (list ?? []).some(entry => String(entry).includes(fragment));
    }

    // With no module loaded: every registry is the core's own list, unchanged
    function _identity(when) {
        assert(WidgetRegistry.entries === WidgetRegistry.coreEntries, when + ": WidgetRegistry.entries is the core's list");
        assertEqual(WidgetRegistry.types.join(","), "power,settings,workspaces,clock,music,sound,bluetooth,tray,network,notifications,hardware,battery,stt",
                    when + ": … its thirteen types");
        assert(SettingsSchema.entries === SettingsSchema.coreEntries, when + ": SettingsSchema.entries is the core's list");
        assertEqual(JSON.stringify(SettingsSchema.defaults), JSON.stringify(SettingsSchema.coreDefaults), when + ": … the defaults the core's");
        assert(ProfileRules.factTypes === ProfileRules.coreFactTypes, when + ": ProfileRules.factTypes is the core's list");
        assertEqual(JSON.stringify(WidgetPresets.defaults), JSON.stringify(WidgetPresets.coreDefaults), when + ": WidgetPresets.defaults the core's");
        assert(!Object.keys(Profiles.facts).some(fact => fact.startsWith("good.")), when + ": no module fact in Profiles.facts");
        assert(_window.pages === _window.corePages, when + ": the settings window's pages are the core's list");
        assertEqual(Modules.host.slotContributions("network.popup.sections").length, 0, when + ": no slot contribution");
    }

    function runAsync() {
        _savedDisabled = Modules.host._plainList(Config.disabledModules);
        _then("the module host suite is done, the config read", () => (after === null || after.done) && Config.ready, () => {
            Config.disabledModules = [];
            const component = Qt.createComponent(Qt.resolvedUrl("../panels/SettingsWindow.qml"), Component.PreferSynchronous);
            _window = component.status === Component.Ready ? component.createObject(suite, { visible: false }) : null;
            assert(_window !== null, "the settings window can be made (" + component.errorString() + ")");
            _identity("no module");
            const empty = _slot("settings.general.bottom");
            assertEqual(empty.count + "," + empty.implicitHeight + "," + empty.visible, "0,0,false", "a slot nobody fills: no size, invisible, nothing built");
            Modules.host.load([fixtures + "/good", fixtures + "/broken-slot"], {});
        });
        _then("good and broken-slot settle", _settled, () => {
            assertEqual(Modules.status("good")?.state, "loaded", "good: loaded in the shell's host");
            // WidgetRegistry
            const entry = WidgetRegistry.entry("good");
            assertEqual(entry?.module, "good", "WidgetRegistry: good's widget type, naming its module");
            assertEqual(WidgetRegistry.widgetUrl("good"), "file://" + fixtures + "/good/GoodWidget.qml", "… its widget by absolute URL");
            assertEqual(WidgetRegistry.popupContent("good"), "good", "… its popup");
            assertEqual(WidgetRegistry.popupPanelUrl("good"), "file://" + fixtures + "/good/GoodPanel.qml", "… its popup panel");
            assertEqual(WidgetRegistry.settingsUrl("good"), "file://" + fixtures + "/good/GoodWidgetSettings.qml", "… its settings pane");
            assert(WidgetRegistry.hasPresets("good") && WidgetRegistry.hasPopupMode("good"), "… presets and a popup mode");
            assertEqual(WidgetRegistry.moduleOf("good") + "," + WidgetRegistry.popupModule("good") + "," + WidgetRegistry.moduleOf("clock"), "good,good,",
                        "… moduleOf, popupModule");
            assertEqual(WidgetRegistry.entries.slice(0, WidgetRegistry.coreEntries.length).map(each => each.type).join(","),
                        WidgetRegistry.coreEntries.map(each => each.type).join(","), "… after the core's, in their order");
            // WidgetPresets
            assertEqual(WidgetPresets.value("good", "", "label"), "G", "WidgetPresets: the module's presetDefaults");
            assertEqual(WidgetPresets.value("clock", "", "format"), "hh:mm:ss", "… the core's untouched");
            // SettingsSchema, Profiles
            assertEqual(SettingsSchema.entry("mod.good.greeting")?.default, "hello", "SettingsSchema: the module's setting");
            assertEqual(SettingsSchema.entry("widgets.good.popupMode")?.default, "click", "… its widget's popup mode entry, made from the registry");
            assertEqual(Profiles.value("mod.good.greeting"), "hello", "Profiles.value: the module setting's default");
            assert(SettingsSchema.systemGlobalDefaults["mod.good.loud"] === false, "… a global one is global");
            assert(!("mod.good.greeting" in SettingsSchema.coreDefaults), "… not among the defaults a new config's Full spells out");
            // Facts
            assertEqual(ProfileRules.factType("good.ready")?.type, "bool", "ProfileRules.factTypes: the module's facts");
            assertEqual(Profiles.facts["good.ready"], true, "Profiles.facts: the fact its main set");
            assert(ProfileRules.matches({ fact: "good.ready", is: true }, Profiles.facts), "… a condition on it holds");
            // Settings window
            const page = _window.pages.find(each => each.id === "good");
            assertEqual(page?.tab + " " + page?.url, "system file://" + fixtures + "/good/GoodSettings.qml", "the settings window: good's page on the System tab, by URL");
            // The handle and the A6 contract
            const handle = Modules.handle("good");
            assert(handle !== null && handle.active, "the handle: active");
            assert(Api.module("good") === handle && Api.moduleAt("file://" + fixtures + "/good/x/Y.qml") === handle, "Api.module, Api.moduleAt: the same handle");
            _main = Modules.host.mainObject("good");
            _goodState = _main.goodState;
            assert(_goodState.ticking && _goodState.registrations.length === 1, "good's timer runs, its registration is in");
            // Slots
            const sections = _slot("network.popup.sections", { wifiEnabled: false });
            assertEqual(sections.count, 1, "a slot: good's contribution");
            const built = sections.items[0];
            assert(built?.ready, "… built");
            assertEqual(built?.item.module, handle, "… with its module's handle");
            assertEqual(built?.item.context.slot + "," + built?.item.context.wifiEnabled, "network.popup.sections,false", "… with the context, slot added");
            assert(built.implicitHeight > 0, "… with its size (the slot's follows when laid out)");
            const changes = built.item.contextChanges;
            sections.context = { wifiEnabled: false };
            assertEqual(built.item.contextChanges, changes, "… the same context again (a new object): not passed");
            sections.context = { wifiEnabled: true };
            assertEqual(built.item.contextChanges, changes + 1, "… a changed one: passed");
            assertEqual(built.item.context.wifiEnabled, true, "… and current");
            const broken = _slot("notifications.popup.top");
            assertEqual(broken.count, 1, "a contribution that does not compile: counted");
            assert(broken.items.length === 1 && !broken.items[0].ready, "… not shown");
            assertEqual(broken.implicitHeight, 0, "… the slot takes no room for it");
            assertEqual(Modules.status("broken-slot")?.state, "loaded", "… which stays loaded");
            // The VPN seam after the merge: a Component per module for a slot
            assert(Modules.slotComponent("network.popup.sections", "good") !== null, "slotComponent: good's contribution as a Component");
            assert(Modules.slotComponent("network.popup.sections", "good") === Modules.slotComponent("network.popup.sections", "good"), "… the same Component while it stays");
            assertEqual(Modules.slotComponent("network.popup.sections", "broken-slot"), null, "… none for a module without one");
            assertEqual(Modules.slotUrl("network.popup.sections", "good"), "file://" + fixtures + "/good/GoodSlot.qml", "slotUrl");
            const wrapped = Modules.slotComponent("network.popup.sections", "good").createObject(suite, { context: { slot: "x", n: 1 } });
            assert(wrapped?.ready && wrapped.item.context.n === 1 && wrapped.item.module === handle, "… built, with the handle and the context set on it");
            wrapped?.destroy();

            // Off
            assert(Modules.setEnabled("good", false), "setEnabled(good, false)");
        });
        _then("good is off", () => Modules.status("good")?.state === "disabled", () => {
            _identity("good off");
            const handle = Modules.handle("good");
            assert(!handle.active, "the handle: not active");
            assertEqual(Modules.host.mainObject("good"), null, "its main destroyed");
            assert(_has(Modules.status("broken-slot")?.errors, "slot notifications.popup.top"), "the contribution that did not compile: recorded in its module's status: " + Modules.status("broken-slot")?.errors.join("; "));
            assertEqual(_slots["network.popup.sections"].count, 0, "its slot contribution gone");
            assertEqual(_slots["network.popup.sections"].implicitHeight, 0, "… the slot empty again");
            assert(!_goodState.ticking, "its singleton's timer stopped (it follows module.active)");
            assertEqual(_goodState.registrations.length, 0, "its registration removed with the main");
            assertEqual(handle.setFact("ready", true) !== "", true, "setFact refused while off");
            suite._ticksAtStop = _goodState.ticks;
            suite._waitUntil = Date.now() + 300;
        });
        _then("nothing of good acted meanwhile", () => Date.now() >= _waitUntil, () => {
            assertEqual(_goodState.ticks, _ticksAtStop, "no tick while off");
            assert(Modules.setEnabled("good", true), "setEnabled(good, true)");
        });
        _then("good is on again", () => Modules.status("good")?.state === "loaded", () => {
            const main = Modules.host.mainObject("good");
            assert(main !== null && main !== _main, "a new main");
            assertEqual(main.goodState.mains + "," + main.goodState.registrations.length, "1,1", "… one, its registration in again");
            assert(main.goodState.ticking, "… its timer running again");
            assertEqual(Profiles.facts["good.ready"], true, "… its fact back");
            assertEqual(WidgetRegistry.entry("good")?.module, "good", "… its widget back");
            assertEqual(_slots["network.popup.sections"].count, 1, "… its slot contribution back");
            assert(_window.pages.some(each => each.id === "good"), "… its settings page back");
            Modules.host.unload();
        });
        _then("unloaded", () => Modules.host.statuses.length === 0, () => {
            _identity("unloaded");
            // The reserved ids against the tree: every IPC target, and every widget type, popup
            // key and settings page id shaped like a module id
            _grep.command = ["sh", "-c", "cd \"$1\" && grep -rhoE 'target: *\"[^\"]+\"' --include=*.qml . | grep -v fixtures | sed 's/.*\"\\(.*\\)\"/\\1/' | sort -u; grep -rlE 'ModuleSlot|ModuleContribution|Modules\\.' screensaver singletons/lock singletons/Lockscreen.qml pam 2>/dev/null | sed 's/^/LOCK:/'",
                             "sh", Quickshell.shellDir];
            _grep.running = true;
        });
        _then("the tree's IPC targets are read", () => _grepped !== null, () => {
            const lockFiles = _grepped.filter(name => name.startsWith("LOCK:"));
            assertEqual(lockFiles.join(", "), "", "nothing of the module system on the lock screen (screensaver/, singletons/lock/, Lockscreen, pam/)");
            const names = _grepped.filter(name => name !== "good" && !name.startsWith("LOCK:"))
                .concat(WidgetRegistry.coreEntries.map(each => each.type), WidgetRegistry.coreEntries.filter(each => each.popup).map(each => each.popup),
                        _window.corePages.map(each => each.id), ["tray-menu"]);
            assert(_grepped.length >= 5, "the core's IPC targets were found (" + _grepped.join(", ") + ")");
            const missing = names.filter((name, index) => names.indexOf(name) === index && ModuleRules.idPattern.test(name)
                                          && !ModuleRules.reservedIds.includes(name));
            assertEqual(missing.join(", "), "", "every IPC target, widget type, popup key and settings page id of the core is a reserved id");
        });
        _clock.start();
    }

    property Process _grep: Process {
        property var found: []
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { if (line.trim() !== "") _grep.found.push(line.trim()); }
        }
        onExited: suite._grepped = found
    }
}
