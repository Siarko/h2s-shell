import QtQuick
import Quickshell
import Quickshell.Io
import qs.api
import qs.components
import qs.singletons
import qs.singletons.network

// The core's registries with modules in them (notes/plans/modules.md, M2), on the shell's own
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
    // The VPN provider suite: its counts of VpnManager's providers must not see this one's
    property var vpnSuite: null
    property var _frame: null

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
    property int _resumes: 0
    property real _waitUntil: 0
    // (API 1.15) A bar of the suite's own: two entries of good's widget on two presets and
    // a popup (panels/Popup.qml), and a loader that builds good's widget as the bar does
    property var _barWindow: null
    property var _popup: null
    property var _widgetA: null
    property var _widgetB: null
    property var _widgetLoader: null
    property int _cycles: 0
    property int _builtBefore: 0
    // The panel-opener fixture's singleton, and how often the suite's popup said opened()
    property var _openerState: null
    property int _openedCount: 0

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
        _dropBar();
        Modules.host.unload();
        Config.disabledModules = _savedDisabled;
        for (const name of Object.keys(_slots))
            _slots[name]?.destroy();
        _window?.destroy();
        finish();
    }

    // The suite's bar: a layer surface in a corner (it moves no windows), the two widgets
    // built from the URL of a module's widget type (good's unless named) as the bar builds
    // them (the handle and the preset set), and a popup on the same screen
    function _makeBar(type) {
        _barWindow = Qt.createQmlObject("import QtQuick; import Quickshell; import Quickshell.Wayland; PanelWindow {"
            + " anchors { top: true; left: true } implicitWidth: 300; implicitHeight: 40; color: \"transparent\";"
            + " exclusionMode: ExclusionMode.Ignore; WlrLayershell.layer: WlrLayer.Overlay; WlrLayershell.namespace: \"h2s-tests\";"
            + " WlrLayershell.keyboardFocus: WlrKeyboardFocus.None; property alias row: row; Row { id: row; spacing: 20 } }", suite);
        const popupComponent = Qt.createComponent(Qt.resolvedUrl("../panels/Popup.qml"), Component.PreferSynchronous);
        _popup = popupComponent.createObject(suite, { popupPosition: 0, popupLength: 0, barScreen: _barWindow.screen ?? Quickshell.screens[0], barEdge: "top" });
        assert(_popup !== null, "the popup can be made (" + popupComponent.errorString() + ")");
        const url = WidgetRegistry.widgetUrl(type ?? "good");
        const widgetComponent = Qt.createComponent(url, Component.PreferSynchronous);
        const make = preset => {
            const widget = widgetComponent.createObject(_barWindow.row, Modules.initialProperties(url, { preset: preset }));
            widget.width = 100;
            widget.height = 40;
            widget.popup = _popup;
            return widget;
        };
        _widgetA = make("Alpha");
        _widgetB = make("Beta");
        assert(_widgetA !== null && _widgetB !== null, (type ?? "good") + "'s widget built twice (" + widgetComponent.errorString() + ")");
        assertEqual(_widgetA.preset + "," + _widgetB.preset, "Alpha,Beta", "… one per preset");
    }

    function _dropBar() {
        _widgetA?.destroy();
        _widgetB?.destroy();
        _popup?.destroy();
        _barWindow?.destroy();
        _widgetLoader?.destroy();
        _widgetA = _widgetB = _popup = _barWindow = _widgetLoader = null;
    }

    // Good's popup on screen with its panel, done animating
    function _panelShown() {
        return _popup?.active === true && _popup.item?.showPopup === true && _goodState.panel !== null && !_goodState.panel.popupAnimating;
    }

    function _popupGone() {
        return _popup?.active === false && _goodState.panel === null;
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
        assertEqual(Modules.host.slotContributions("network.vpn.card").length, 0, when + ": no slot contribution");
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
            // API 1.3: a module writes its widget's existing presets through its handle
            {
                const savedPresets = Config.widgetPresets;
                const goodHandle = Modules.handle("good");
                assert(goodHandle.setPresetValue("good", "Mine", "label", "H") !== "", "setPresetValue: no such preset, refused (never created)");
                assert(!WidgetPresets.exists("good", "Mine"), "… and none made");
                WidgetPresets.create("good", "Mine");
                assertEqual(goodHandle.setPresetValue("good", "Mine", "label", "H"), "", "… an existing preset: written");
                assertEqual(goodHandle.presetValue("good", "Mine", "label"), "H", "presetValue: its value");
                assertEqual(goodHandle.presetValue("good", "Mine", "count"), 3, "… a key it does not set: the default");
                assertEqual(goodHandle.setPresetValue("good", "Mine", "label", undefined), "", "undefined removes a key");
                assertEqual(goodHandle.presetValue("good", "Mine", "label"), "G", "… back to the default");
                assert(goodHandle.setPresetValue("good", "Mine", "bad key", 1) !== "", "a key that is not a name: refused");
                assert(goodHandle.setPresetValue("good", "Mine", "__proto__", { polluted: true }) !== "", "… __proto__ as a key: refused");
                for (let i = 0; i < 49; i++)
                    goodHandle.setPresetValue("good", "Mine", "k" + i, i);
                assertEqual(Object.keys(WidgetPresets.stored("good", "Mine")).length, 49, "49 keys written");
                assertEqual(goodHandle.setPresetValue("good", "Mine", "k49", 49), "", "… the 50th: still fine");
                assert(goodHandle.setPresetValue("good", "Mine", "k50", 50) !== "", "… a 51st: refused (the preset as a whole, after the write)");
                assert(goodHandle.setPresetValue("good", "Mine", "k0", "x".repeat(17 * 1024)) !== "", "… larger than 16 KiB after the write: refused");
                assertEqual(goodHandle.setPresetValue("good", "Mine", "k0", undefined), "", "… removing a key always fits");
                // __proto__ and inherited names are never presets (own properties only)
                assert(!WidgetPresets.exists("good", "__proto__") && !WidgetPresets.exists("good", "constructor")
                       && !WidgetPresets.exists("clock", "toString"), "WidgetPresets.exists: never an inherited property");
                assert(goodHandle.setPresetValue("good", "__proto__", "label", "x") !== "", "setPresetValue: the name __proto__ refused");
                WidgetPresets.set("good", "__proto__", "polluted", true);
                WidgetPresets.create("good", "__proto__");
                assert(({}).polluted === undefined && !WidgetPresets.exists("good", "__proto__"), "WidgetPresets.set and create: __proto__ does nothing");
                assertEqual(WidgetPresets.value("good", "constructor", "label"), "G", "WidgetPresets.value: an inherited name reads the default");
                assertEqual(goodHandle.presetValue("clock", "", "format"), undefined, "presetValue: another's type, nothing");
                Config.widgetPresets = savedPresets;
            }
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
            const sections = _slot("network.vpn.card", { wifiEnabled: false });
            assertEqual(sections.count, 1, "a slot: good's contribution");
            const built = sections.items[0];
            assert(built?.ready, "… built");
            assertEqual(built?.item.module, handle, "… with its module's handle");
            assertEqual(built?.item.context.slot + "," + built?.item.context.wifiEnabled, "network.vpn.card,false", "… with the context, slot added");
            assert(built.implicitHeight > 0, "… with its size (the slot's follows when laid out)");
            const changes = built.item.contextChanges;
            sections.context = { wifiEnabled: false };
            assertEqual(built.item.contextChanges, changes, "… the same context again (a new object): not passed");
            sections.context = { wifiEnabled: true };
            assertEqual(built.item.contextChanges, changes + 1, "… a changed one: passed");
            assertEqual(built.item.context.wifiEnabled, true, "… and current");
            const broken = _slot("network.vpn.row");
            assertEqual(broken.count, 1, "a contribution that does not compile: counted");
            assert(broken.items.length === 1 && !broken.items[0].ready, "… not shown");
            assertEqual(broken.implicitHeight, 0, "… the slot takes no room for it");
            assertEqual(Modules.status("broken-slot")?.state, "loaded", "… which stays loaded");
            // The VPN seam after the merge: a Component per module for a slot
            assert(Modules.slotComponent("network.vpn.card", "good") !== null, "slotComponent: good's contribution as a Component");
            assert(Modules.slotComponent("network.vpn.card", "good") === Modules.slotComponent("network.vpn.card", "good"), "… the same Component while it stays");
            assertEqual(Modules.slotComponent("network.vpn.card", "broken-slot"), null, "… none for a module without one");
            assertEqual(Modules.slotUrl("network.vpn.card", "good"), "file://" + fixtures + "/good/GoodSlot.qml", "slotUrl");
            const wrapped = Modules.slotComponent("network.vpn.card", "good").createObject(suite, { context: { slot: "x", n: 1 } });
            assert(wrapped?.ready && wrapped.item.context.n === 1 && wrapped.item.module === handle, "… built, with the handle and the context set on it");
            wrapped?.destroy();
            // API 1.2: `shown` passed to a contribution that declares it, following where it sits
            assertEqual(built.item.shown, built.shown, "shown: passed to a contribution that declares it");
            assertEqual(built.shown, false, "… false where no window shows it (the suite's slot is in none)");
            // API 1.2: resumed() on the handle of an active module when the machine wakes
            suite._resumes = 0;
            handle.resumed.connect(() => suite._resumes++);
            SystemSleep.reportResumed();
            assertEqual(_resumes, 1, "module.resumed(): told when the machine wakes (SystemSleep)");
            // A module widget's popup mode: in the schema with the module, never in the core's
            // entries or defaults (a new config's Full must not freeze it)
            assertEqual(SettingsSchema.entry("widgets.good.popupMode")?.module, "good", "a module widget's popup mode: in the schema, with its module");
            assert(!SettingsSchema.coreEntries.some(entry => entry.key === "widgets.good.popupMode"), "… never among the core's entries");
            assert(!("widgets.good.popupMode" in SettingsSchema.coreDefaults), "… nor the core's defaults");
            assert("widgets.clock.popupMode" in SettingsSchema.coreDefaults || !WidgetRegistry.coreEntries.some(entry => entry.type === "clock" && entry.popup),
                   "… while a core widget's is");
            // Facts: setting the value it has publishes nothing
            const factsBefore = Modules.host.factValues;
            assertEqual(handle.setFact("ready", true), "", "setFact: the same value again");
            assert(Modules.host.factValues === factsBefore, "… a no-op: factValues not reassigned (no setting binding re-evaluated)");
            assertEqual(ModuleLists.factValues["good.ready"], true, "Profiles' facts come from ModuleLists (plain values the host feeds)");
            assert(ModuleLists.settled, "… which says when the modules have settled");

            // API 1.15: module.main, the object made from its manifest's main
            assert(handle.main !== null && handle.main === _main, "module.main: the main object, while the module is active");
            assertEqual(handle.main.module, handle, "… the one given this handle");
            try {
                handle.main = null;
            } catch (error) {}
            assert(handle.main === _main, "… read-only");
            // Written as another module could, through Api.module: nothing changes
            const reached = Api.module("good");
            try {
                reached._main = null;
            } catch (error) {}
            assert(handle.main === _main, "… nor through a store of the handle's (`_main`)");
            try {
                reached.moduleId = "broken-slot";
            } catch (error) {}
            assertEqual(handle.moduleId, "good", "its moduleId: read-only");
            try {
                reached.host = null;
            } catch (error) {}
            assert(handle.host === Modules.host && handle.active, "its host: read-only");

            // API 1.15: what a popup panel is given
            _makeBar();
            _widgetA.togglePopup(false);
        });
        _then("good's popup shows, opened from the entry on Alpha", _panelShown, () => {
            const opener = _goodState.panelOpenerAtStart;
            assertEqual(JSON.stringify(opener), JSON.stringify({ widgetType: "good", preset: "Alpha", edge: "top", byTouch: false }),
                        "opener: the widget that opened it, before the panel completed");
            assert(Object.isFrozen(opener), "… frozen");
            assert(_goodState.panel.opener === opener, "… and still the panel's");
            assertEqual(_goodState.panel.module, Modules.handle("good"), "the panel has its module's handle");
            assert(_goodState.panel.availableHeight > 0 && _goodState.panel.availableHeight === _popup.item.availableContentHeight,
                   "availableHeight: the popup's (" + _goodState.panel.availableHeight + ")");
            assertEqual(_goodState.panel.height, Math.max(0, _popup.item.shownContentHeight), "fitsShownHeight: the panel is the height shown");
            assert(_goodState.panelSawAnimating, "popupAnimating: true while the popup opened");
            assertEqual(_goodState.panel.popupAnimating, false, "… false once it is still");
            assert(_widgetA.popupOpen, "the widget: its popup open");
            _builtBefore = _goodState.panelsBuilt;
            // The same panel told of another opener: the other entry, by hover
            _widgetB.popupMode = "hover";
            _widgetB.hover(true);
        });
        _then("the open panel is told its new opener", () => _goodState.panel?.opener?.preset === "Beta", () => {
            assertEqual(_goodState.panelsBuilt, _builtBefore, "… not built again");
            assertEqual(JSON.stringify(_goodState.panel.opener), JSON.stringify({ widgetType: "good", preset: "Beta", edge: "top", byTouch: false }),
                        "… the entry on Beta");
            const same = _goodState.panel.opener;
            _widgetB.hover(true);
            assert(_goodState.panel.opener === same, "… opened again from the same entry: the object unchanged");
            _widgetB.popupMode = "click";
            _widgetB.togglePopup(false);
        });
        _then("the popup closes", _popupGone, () => {
            assertEqual(_goodState.panelsGone, _goodState.panelsBuilt, "its panel destroyed with it");
            _widgetB.togglePopup(true);
        });
        _then("good's popup shows again, opened by a tap on Beta", _panelShown, () => {
            assertEqual(JSON.stringify(_goodState.panelOpenerAtStart), JSON.stringify({ widgetType: "good", preset: "Beta", edge: "top", byTouch: true }),
                        "a new panel: the opener of the entry on Beta, by touch");
            _widgetB.togglePopup(true);
        });
        // Opened and closed again and again, from either entry: each time a panel is built (from
        // Qt.callLater, the Repeater rules) and destroyed, and the shell stays up
        for (let i = 0; i < 6; i++) {
            _then("closed, cycle " + i, _popupGone, () => (i % 2 === 0 ? _widgetA : _widgetB).togglePopup(i % 3 === 0));
            _then("open, cycle " + i, _panelShown, () => {
                assertEqual(_goodState.panelOpenerAtStart?.preset, i % 2 === 0 ? "Alpha" : "Beta", "cycle " + i + ": its opener's preset");
                suite._cycles++;
                (i % 2 === 0 ? _widgetA : _widgetB).togglePopup(false);
            });
        }
        _then("closed after the cycles", _popupGone, () => {
            assertEqual(_cycles, 6, "six popups opened and closed");
            assertEqual(_goodState.panelsGone, _goodState.panelsBuilt, "… every panel built destroyed");
            _widgetA.destroy();
            _widgetB.destroy();
            _popup.destroy();
            _barWindow.destroy();
            _widgetA = _widgetB = _popup = _barWindow = null;
            // Good's widget built as the bar builds it (by URL from the registry, following it):
            // turned on again, it is built within the host's publishing, after the main
            _widgetLoader = Qt.createQmlObject("import QtQuick; import qs.singletons; Loader {"
                + " readonly property string _url: WidgetRegistry.widgetUrl(\"good\");"
                + " function _load() { if (_url === \"\") source = \"\"; else setSource(_url, Modules.initialProperties(_url)); }"
                + " on_UrlChanged: _load(); Component.onCompleted: _load() }", suite);
            assert(_widgetLoader.item !== null, "the loader built good's widget");

            // Off
            assert(Modules.setEnabled("good", false), "setEnabled(good, false)");
        });
        // The main is destroyed later (deleteLater), its children's onDestruction with it: wait for
        // that rather than looking in the same tick
        _then("good is off", () => Modules.status("good")?.state === "disabled" && _goodState.registrations.length === 0, () => {
            _identity("good off");
            const handle = Modules.handle("good");
            assert(!handle.active, "the handle: not active");
            assertEqual(Modules.host.mainObject("good"), null, "its main destroyed");
            assertEqual(handle.main, null, "module.main: null while off");
            assertEqual(_widgetLoader.item, null, "the bar's widget gone with its type");
            _goodState.widgetSawMain = null;
            SystemSleep.reportResumed();
            assertEqual(_resumes, 1, "resumed(): not told while the module is off");
            assert(_has(Modules.status("broken-slot")?.errors, "slot network.vpn.row"), "the contribution that did not compile: recorded in its module's status: " + Modules.status("broken-slot")?.errors.join("; "));
            assertEqual(_slots["network.vpn.card"].count, 0, "its slot contribution gone");
            assertEqual(_slots["network.vpn.card"].implicitHeight, 0, "… the slot empty again");
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
            assert(Modules.handle("good").main === main, "module.main: the new main");
            assert(_widgetLoader.item !== null && _goodState.widgetSawMain === main,
                   "… set before the module's widget completed (built as the module came back)");
            _widgetLoader.destroy();
            _widgetLoader = null;
            assertEqual(main.goodState.mains + "," + main.goodState.registrations.length, "1,1", "… one, its registration in again");
            assert(main.goodState.ticking, "… its timer running again");
            assertEqual(Profiles.facts["good.ready"], true, "… its fact back");
            assertEqual(WidgetRegistry.entry("good")?.module, "good", "… its widget back");
            assertEqual(_slots["network.vpn.card"].count, 1, "… its slot contribution back");
            assert(_window.pages.some(each => each.id === "good"), "… its settings page back");
            Modules.host.unload();
        });
        _then("unloaded", () => Modules.host.statuses.length === 0, () => {
            _identity("unloaded");
            // The reserved ids against the tree: every IPC target, and every widget type, popup
            // key and settings page id shaped like a module id
            _grep.command = ["sh", "-c", "cd \"$1\" && grep -rhoE 'target: *\"[^\"]+\"' --include=*.qml . | grep -v fixtures | sed 's/.*\"\\(.*\\)\"/\\1/' | sort -u; sh tests/lock-closure.sh .; t=$(mktemp -d -p \"${XDG_RUNTIME_DIR:-/tmp}\") && mkdir -p $t/screensaver $t/components && printf 'import QtQuick\\nimport qs.components\\nItem {\\n    Shared { }\\n    Picker { }\\n    Paged { }\\n}\\n' > $t/screensaver/A.qml && printf 'import QtQuick\\nItem { SettingsPage {} }\\n' > $t/components/Paged.qml && printf 'import QtQuick\\nItem { Inner {} }\\n' > $t/components/Shared.qml && printf 'import QtQuick\\nItem { ModuleSlot {} }\\n' > $t/components/Inner.qml && printf 'import QtQuick\\nItem { Component.onCompleted: FileChooser.open }\\n' > $t/components/Picker.qml && sh tests/lock-closure.sh $t | sed 's/^/SELFTEST:/'; rm -rf $t",
                             "sh", Quickshell.shellDir];
            _grep.running = true;
        });
        _then("the tree's IPC targets are read", () => _grepped !== null, () => {
            const lockFiles = _grepped.filter(name => name.startsWith("LOCK:"));
            assertEqual(lockFiles.join(", "), "", "nothing of the module system on the lock screen (screensaver/, singletons/lock/, Lockscreen, pam/ and the components they build, transitively: tests/lock-closure.sh)");
            const walked = Number((_grepped.find(name => name.startsWith("LOCKFILES:")) ?? "LOCKFILES:0").slice(10));
            assert(walked >= 10, "… the walk reached the lock screen's files and what they build (" + walked + ")");
            assert(_grepped.includes("SELFTEST:LOCK:components/Inner.qml"),
                   "… and catches a ModuleSlot in a component a lock file builds through another (a made-up tree): " + _grepped.filter(name => name.startsWith("SELFTEST")).join(", "));
            assert(_grepped.includes("SELFTEST:LOCK:components/Paged.qml"),
                   "… and an anchor block (whose hosts build modules' elements) in a component a lock file builds (a made-up tree): " + _grepped.filter(name => name.startsWith("SELFTEST")).join(", "));
            assert(_grepped.includes("SELFTEST:LOCK:components/Picker.qml"),
                   "… and the file chooser in a component a lock file builds (a made-up tree): " + _grepped.filter(name => name.startsWith("SELFTEST")).join(", "));
            const names = _grepped.filter(name => name !== "good" && !/^(LOCK|LOCKFILES|SELFTEST):/.test(name))
                .concat(WidgetRegistry.coreEntries.map(each => each.type), WidgetRegistry.coreEntries.filter(each => each.popup).map(each => each.popup),
                        _window.corePages.map(each => each.id), ["tray-menu"]);
            assert(_grepped.length >= 5, "the core's IPC targets were found (" + _grepped.join(", ") + ")");
            const missing = names.filter((name, index) => names.indexOf(name) === index && ModuleRules.idPattern.test(name)
                                          && !ModuleRules.reservedIds.includes(name));
            assertEqual(missing.join(", "), "", "every IPC target, widget type, popup key and settings page id of the core is a reserved id");
            Modules.host.load([fixtures + "/panel-opener"], {});
        });

        // (API 1.15) A popup panel whose root declares `opener` readonly: never given one —
        // its status says so — and opened again from another entry by hover, the popup still
        // moves there, stays open and says opened()
        _then("panel-opener settles", _settled, () => {
            const status = Modules.status("panel-opener");
            assertEqual(status?.state, "loaded", "panel-opener: loaded");
            assert(_has(status?.warnings, "ReadonlyOpenerPanel.qml: its root declares `readonly property var opener`"),
                   "… with a warning naming its panel's readonly opener: " + JSON.stringify(status?.warnings));
            _makeBar("panel-opener");
            _openerState = _widgetA.openerState;
            _popup.opened.connect(() => suite._openedCount++);
            _widgetA.togglePopup(false);
        });
        _then("its popup shows, opened from the entry on Alpha",
              () => _popup?.active === true && _popup.item?.showPopup === true && _openerState.panel !== null && _popup.item.animating === false, () => {
            assertEqual(_openerState.panel.opener, null, "a readonly opener: not given one at its first build");
            const before = _openedCount;
            _widgetB.popupMode = "hover";
            _widgetB.hover(true);
            assertEqual(_openedCount, before + 1, "opened again from Beta by hover: opened() said");
            assertEqual(_popup.popupPosition, _widgetB.mapToItem(null, 0, 0).x, "… the popup moved to Beta's entry");
            assert(_popup.active && !_popup.closing, "… and stays open");
            assertEqual(_openerState.panel.opener, null, "… its opener not written (decided as at its first build)");
            assert(!_has(Modules.status("panel-opener")?.errors, "opener"), "… no error: nothing was tried");
            _widgetB.popupMode = "click";
            _widgetB.togglePopup(false);
        });
        _then("its popup closes", () => _popup?.active === false && _openerState.panel === null, () => {
            _dropBar();
            Modules.host.unload();
        });
        _then("panel-opener unloaded", () => Modules.host.statuses.length === 0, () => {});

        // The VPN slots (API 1.1): a module's provider (providerId = its id) fills them through
        // its manifest; a provider that is no module's keeps its own. After the VPN provider
        // suite, which counts VpnManager's providers.
        _then("the VPN provider suite is done", () => vpnSuite === null || vpnSuite.done, () => {
            assert(Api.slots.some(slot => slot.name === "network.vpn.row" && slot.since === "1.1")
                   && Api.slots.some(slot => slot.name === "network.vpn.card") && Api.slots.some(slot => slot.name === "network.vpn.page"),
                   "the slot table offers network.vpn.row, .card and .page (since 1.1)");
            Modules.host.load([fixtures + "/vpn-slots", fixtures + "/vpn-page"], {});
        });
        _then("vpn-slots and vpn-page settle, their providers registered", () => _settled() && VpnManager.providerOf("vpn-slots:one") !== null
                                                                         && VpnManager.providerOf("vpn-page:one") !== null, () => {
            const status = Modules.status("vpn-slots");
            assertEqual(status?.state, "loaded", "vpn-slots: loaded (api 1.1)");
            assertEqual(JSON.stringify(status?.warnings ?? null), "[]", "… no warning: its main extends VpnProvider from qs.components, its slots are offered");
            assertEqual(JSON.stringify(status?.deprecations ?? null),
                        JSON.stringify(["import qs.components (in Main.qml): use the elements of qs.api (goes with the shell's next tightening)"]),
                        "… but that import is listed among its deprecations, and it loaded all the same");
            assertEqual(JSON.stringify(Modules.host.describe().modules.find(module => module.id === "vpn-slots")?.deprecations ?? null), JSON.stringify(status.deprecations),
                        "… as `modules list` prints them");
            assertEqual(JSON.stringify(Modules.status("vpn-page")?.deprecations ?? null) + " " + Modules.status("vpn-page")?.state, "[] loaded",
                        "vpn-page, whose provider extends VpnProvider from qs.api: loaded, nothing deprecated");
            const vpn = VpnManager.vpns.find(each => each.uuid === "vpn-slots:one") ?? null;
            assert(vpn !== null, "its provider's entry is among the VPNs");
            const row = VpnManager.extrasFor(VpnManager.slots.row, vpn);
            assert(row !== null && row === Modules.slotComponent("network.vpn.row", "vpn-slots"), "extrasFor(row): the module's contribution (Modules.slotComponent)");
            assert(VpnManager.extrasFor(VpnManager.slots.card, vpn) === Modules.slotComponent("network.vpn.card", "vpn-slots"), "extrasFor(card): the module's");
            assertEqual(VpnManager.extrasFor(VpnManager.slots.page, vpn), null, "extrasFor(page): none (the page is loaded by URL)");
            assertEqual(VpnManager.pageOf(vpn), "file://" + fixtures + "/vpn-slots/VpnPage.qml", "pageOf: the module's page (Modules.slotUrl)");
            assertEqual(VpnManager.settingsPageOf(vpn), "", "settingsPageOf: none — vpn-slots names no settings page (the frame is its way)");
            // A provider whose page is a regular settings page (settingsPage, no page slot):
            // "Settings…" goes there — the list selects it — and no framed copy is offered
            const paged = VpnManager.vpns.find(each => each.uuid === "vpn-page:one") ?? null;
            const listed = _window.pages.find(each => each.id === "vpn-page") ?? null;
            assertEqual(listed?.parent + " " + listed?.tab, "network system", "vpn-page's settings page: in the window's list under Network (System), beside VPN");
            assert(Shell.settingsPageIds.includes("vpn-page"), "… published to Shell.settingsPageIds by the window");
            assertEqual(VpnManager.settingsPageOf(paged), "vpn-page", "settingsPageOf: the module's page, known to the window");
            assertEqual(VpnManager.pageOf(paged), "", "pageOf: no framed copy");
            // What shell.qml does with Shell.openSettings, on the suite's window
            const go = pageId => _window.selectedPage = pageId;
            Shell.openSettings.connect(go);
            _window.selectedPage = "network_vpn";
            const navigated = VpnManager.openSettingsPageOf(paged);
            Shell.openSettings.disconnect(go);
            assert(navigated && _window.selectedPage === "vpn-page", "Settings… on its card: the window's selected page is the module's (" + _window.selectedPage + ")");
            const context = VpnManager.contextFor(VpnManager.slots.row, vpn);
            assert(context.provider === VpnManager.providerOf(vpn).object && Array.isArray(context.otherVpnsUp), "contextFor: the provider, otherVpnsUp");
            const built = row.createObject(suite, { context: context });
            assert(built?.ready && built.item.text === "Row of vpn-slots:one by vpn-slots", "… built in the module's guard, with its handle and the context: " + built?.item?.text);
            built?.destroy();
            // A provider that is no module's: its own extras
            const fakeComponent = Qt.createComponent(Qt.resolvedUrl("FakeVpnProvider.qml"), Component.PreferSynchronous);
            const fake = fakeComponent.createObject(suite, { providerId: "vpt-own", withExtras: true, withPage: true });
            fake.add("x", "Own extras");
            const own = VpnManager.vpns.find(each => each.uuid === "vpt-own:x") ?? null;
            assert(own !== null && VpnManager.extrasFor(VpnManager.slots.row, own) === fake.rowExtras
                   && VpnManager.extrasFor(VpnManager.slots.card, own) === fake.cardExtras, "a provider that is no module's: its own rowExtras and cardExtras");
            assert(VpnManager.pageOf(own).endsWith("/tests/FakeVpnProviderPage.qml"), "… and its own pageUrl");
            fake.destroy();
            // The page in the core's frame, given its module's handle
            const frameComponent = Qt.createComponent(Qt.resolvedUrl("../panels/settings/VpnProviderPageFrame.qml"), Component.PreferSynchronous);
            _frame = frameComponent.createObject(suite, { vpnId: "vpn-slots:one", width: 400, height: 300 });
            assert(_frame !== null, "the page frame can be made (" + frameComponent.errorString() + ")");
        });
        _then("the frame shows the module's page", () => _frame?.page !== null && _frame?.page !== undefined, () => {
            assertEqual(_frame.page.objectName, "vpnSlotsPage", "the frame loaded the module's page");
            assertEqual(_frame.page.module, Modules.handle("vpn-slots"), "… and handed it its module's handle (it declares `module`)");
            assertEqual(_frame.page.context?.vpnId, "vpn-slots:one", "… and its context");
            assert(Modules.setEnabled("vpn-slots", false), "setEnabled(vpn-slots, false)");
            assert(Modules.setEnabled("vpn-page", false), "setEnabled(vpn-page, false) while its page is open");
        });
        _then("vpn-slots and vpn-page are off", () => Modules.status("vpn-slots")?.state === "disabled" && Modules.status("vpn-page")?.state === "disabled", () => {
            assertEqual(_window.selectedPage, "general", "vpn-page off while its page was open: the settings window falls back (General), as for any page that went");
            assert(!Shell.settingsPageIds.includes("vpn-page"), "… and its page left Shell.settingsPageIds");
            assertEqual(VpnManager.providerOf("vpn-page:one"), null, "… its provider with it");
            assertEqual(VpnManager.providerOf("vpn-slots:one"), null, "its provider left with its main");
            assertEqual(Modules.slotComponent("network.vpn.row", "vpn-slots"), null, "… its slot contributions with the module");
            Modules.setEnabled("vpn-slots", true);
            Modules.setEnabled("vpn-page", true);
            _frame?.destroy();
            _frame = null;
            Modules.host.unload();
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
