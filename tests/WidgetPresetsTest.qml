import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

// The widget preset library's bindings: "on.<interaction>" keys in a preset, the type's
// defaults they fall back to (declared bindings and what the popup implies, from the active
// profile's popup mode), the lookup a bar entry reads in a binding, and the log line for a
// binding that fails its shape check. A config written before bindings
// (tests/fixtures/widget-bindings/existing-config.json) gives every bar entry what its clicks
// and hover did before. The rules alone: InteractionRulesTest.
TestCase {
    id: suite
    suiteName: "WidgetPresets"

    readonly property var toggle: ({ mode: "single", action: { action: "shell:popup.toggle" } })
    readonly property var open: ({ mode: "single", action: { action: "shell:popup.open" } })
    readonly property var settingsToggle: ({ mode: "single", action: { action: "shell:settings.toggle" } })

    property FileView _file: FileView {
        blockAllReads: true
        printErrors: false
    }

    function _json(relative) {
        _file.path = Quickshell.shellDir + "/" + relative;
        _file.reload();
        const text = _file.text();
        _file.path = "";
        try {
            return JSON.parse(text);
        } catch (error) {
            return null;
        }
    }

    // A bar entry's lookup, read in a binding: follows the preset library and the profiles
    property string _probeType: "clock"
    property string _probePreset: ""
    readonly property var _probe: WidgetPresets.bindingLookup(_probeType, _probePreset)

    function _text(value) {
        return JSON.stringify(value);
    }

    function run() {
        const savedProfiles = Config.profiles;
        const savedPresets = Config.widgetPresets;
        try {
            _existingConfig();
            _readPath();
            _profiles();
            _problemsLogged();
        } finally {
            Config.profiles = savedProfiles;
            Config.widgetPresets = savedPresets;
        }
    }

    // What every entry of a config written before bindings runs: what it did before
    function _existingConfig() {
        const fixture = _json("tests/fixtures/widget-bindings/existing-config.json");
        assert(fixture !== null, "the fixture reads");
        if (fixture === null)
            return;
        Config.profiles = JSON.stringify(fixture.profiles);
        Config.widgetPresets = JSON.stringify(fixture.widgetPresets);
        const named = { toggle: toggle, open: open };
        const sections = fixture.profiles[0].set;
        const seen = [];
        for (const side of ["left", "center", "right"]) {
            sections["bar." + side].forEach((entry, index) => {
                const label = side + "/" + index + " " + entry.type;
                seen.push(label);
                const look = WidgetPresets.bindingLookup(entry.type, entry.preset);
                const wanted = fixture.expected[label];
                if (typeof wanted === "string") {
                    assertEqual(look, null, label + ": " + wanted);
                    return;
                }
                const found = {};
                for (const interaction of InteractionRules.interactions()) {
                    const binding = look(interaction);
                    if (binding !== undefined)
                        found[interaction] = binding;
                }
                const tap = InteractionRules.effective("tap", look).binding;
                if (tap !== undefined)
                    found.tap = tap;
                const expected = {};
                for (const key of Object.keys(wanted))
                    expected[key] = named[wanted[key]];
                assertEqual(_text(found), _text(expected), label + ": runs what it did before bindings");
            });
        }
        assertEqual(seen.join(","), Object.keys(fixture.expected).join(","), "every entry of the fixture checked");
        assertEqual(new Set(seen.map(label => label.split(" ")[1])).size, WidgetRegistry.coreEntries.length, "… every core widget type among them");
        assertEqual(WidgetPresets.value("clock", "Clock 1", "format"), "hh:mm", "the widgets' own preset keys read as before");
        assertEqual(WidgetPresets.value("clock", "", "format"), "hh:mm:ss", "… and their defaults");
    }

    // The lookup in a binding follows edits of the preset, the entry's preset and the popup mode
    function _readPath() {
        Config.profiles = JSON.stringify([{ name: "Full", set: {} }]);
        Config.widgetPresets = JSON.stringify({ clock: { "Clock 1": { format: "hh:mm" } } });
        _probeType = "clock";
        _probePreset = "Clock 1";
        assertEqual(_text(_probe("leftClick")), _text(toggle), "a preset without binding keys: the popup's default (click)");
        assertEqual(_text(WidgetPresets.value("clock", "", "on.leftClick")), _text(toggle), "… a binding key among the type's preset defaults");
        WidgetPresets.set("clock", "Clock 1", "on.middleClick", settingsToggle);
        assertEqual(_text(_probe("middleClick")), _text(settingsToggle), "a binding written to the preset: the lookup follows");
        assertEqual(_text(_probe("leftClick")), _text(toggle), "… the keys it does not set still the defaults");
        WidgetPresets.set("clock", "Clock 1", "on.leftClick", null);
        assertEqual(_probe("leftClick"), null, "a key set to nothing: nothing");
        WidgetPresets.set("clock", "Clock 1", "on.leftClick", undefined);
        assertEqual(_text(_probe("leftClick")), _text(toggle), "the key removed: the default again");
        WidgetPresets.set("clock", "Clock 1", "on.leftClick", { mode: "single", action: "shell:popup.toggle" });
        assertEqual(_text(_probe("leftClick")), _text(toggle), "a key failing its shape check: the default");
        _probePreset = "";
        assertEqual(_probe("middleClick"), undefined, "the entry without a preset: the defaults only");
        _probePreset = "Gone";
        assertEqual(_text(_probe("leftClick")), _text(toggle), "a preset that does not exist: the defaults");
        _probeType = "tray";
        assertEqual(_probe, null, "the tray's cell takes no interactions: no lookup");
        _probeType = "settings";
        assertEqual(_probe("leftClick"), undefined, "a type without a popup or declared bindings: unassigned");
        WidgetPresets.create("settings", "Settings 1");
        WidgetPresets.set("settings", "Settings 1", "on.rightClick", settingsToggle);
        _probePreset = "Settings 1";
        assertEqual(_text(_probe("rightClick")), _text(settingsToggle), "… a preset of it holds bindings");
        _probeType = "clock";
        _probePreset = "Clock 1";
        Config.profiles = JSON.stringify([{ name: "Full", set: { "widgets.clock.popupMode": "hover" } }]);
        assertEqual(_text(_probe("hover")) + _text(_probe("leftClick")), _text(open) + "undefined", "the popup mode set to hover: the lookup follows");
        assertEqual(_text(_probe("middleClick")), _text(settingsToggle), "… the preset's own binding kept");
        assertEqual(_text(InteractionRules.effective("tap", _probe).binding), _text(toggle), "… a tap still toggles the popup");
    }

    // Profiles differ by naming another preset; a preset's content is shared by each that
    // names it; the popup's default follows the active profile
    function _profiles() {
        const tablet = { mode: "single", action: { action: "shell:tabletMode.toggle" } };
        Config.widgetPresets = JSON.stringify({ clock: { "Clock 1": {}, "Clock tablet": { "on.touchHold": tablet } } });
        const profiles = [
            { name: "Full", set: { "bar.left": [{ type: "clock", preset: "Clock 1" }] } },
            { name: "Tablet", when: { fact: "input.tabletMode", is: true },
              set: { "bar.left": [{ type: "clock", preset: "Clock tablet" }], "widgets.clock.popupMode": "none" } }
        ];
        Config.profiles = JSON.stringify(profiles);
        const entryLookup = () => {
            const entry = Profiles.value("bar.left")[0];
            return WidgetPresets.bindingLookup(entry.type, entry.preset);
        };
        assertEqual(Profiles.value("bar.left")[0].preset, "Clock 1", "the Full profile active: its entry names Clock 1");
        assertEqual(_text(entryLookup()("leftClick")) + _text(entryLookup()("touchHold")), _text(toggle) + "undefined", "… its bindings: the defaults");
        const savedSimulated = Profiles.simulated;
        Profiles.simulated = Object.assign({}, savedSimulated, { "input.tabletMode": true });
        try {
            assertEqual(Profiles.value("bar.left")[0].preset, "Clock tablet", "the Tablet profile active: its entry names another preset");
            assertEqual(_text(entryLookup()("touchHold")), _text(tablet), "… whose binding it runs");
            assertEqual(entryLookup()("leftClick"), undefined, "… and the popup's default follows that profile's popup mode (none)");
        } finally {
            Profiles.simulated = savedSimulated;
        }
        assertEqual(_text(entryLookup()("leftClick")), _text(toggle), "back to Full: its default again");
    }

    // A binding failing its shape check: one log line when it appears, none while it stays
    function _problemsLogged() {
        Config.profiles = JSON.stringify([{ name: "Full", set: {} }]);
        Config.widgetPresets = JSON.stringify({});
        const before = WidgetPresets.problemLinesLogged;
        WidgetPresets.create("music", "Music 1");
        WidgetPresets.set("music", "Music 1", "on.middleClick", { mode: "single", action: "own:playPause" });
        assertEqual(WidgetPresets.problemLinesLogged - before, 1, "a binding failing its shape check: one log line");
        assertEqual(_text(WidgetPresets.bindingProblems), _text([{ type: "music", name: "Music 1", key: "on.middleClick" }]), "… named in bindingProblems");
        WidgetPresets.set("music", "Music 1", "on.hover", toggle);
        WidgetPresets.set("music", "Music 1", "note", "x");
        assertEqual(WidgetPresets.problemLinesLogged - before, 1, "… other edits of the preset log it no more");
        WidgetPresets.set("music", "Music 1", "on.rightClick", { mode: "cycle", actions: [] });
        assertEqual(WidgetPresets.problemLinesLogged - before, 2, "a second one: one line more");
        WidgetPresets.set("music", "Music 1", "on.middleClick", undefined);
        WidgetPresets.set("music", "Music 1", "on.middleClick", { mode: "single", action: "own:playPause" });
        assertEqual(WidgetPresets.problemLinesLogged - before, 3, "gone and back: logged again");
        WidgetPresets.set("tray", "Tray 1", "on.middleClick", 5);
        WidgetPresets.set("nonexistent", "X", "on.middleClick", 5);
        assertEqual(WidgetPresets.problemLinesLogged - before, 3, "a type without cell interactions, or unknown: not checked");
    }
}
