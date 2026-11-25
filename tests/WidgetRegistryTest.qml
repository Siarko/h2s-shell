import QtQuick
import qs.singletons

// Every file the registry names must exist and compile. A typo or a forgotten file used
// to break one widget silently at runtime; here it fails the suite.
TestCase {
    suiteName: "WidgetRegistry"

    function _compiles(url, label) {
        if (!url) {
            fail(label + ": no URL");
            return;
        }
        const component = Qt.createComponent(url);
        if (component.status === Component.Ready)
            assert(true, label + " compiles");
        else
            fail(label + " does not compile: " + component.errorString().trim());
    }

    function run() {
        const types = WidgetRegistry.types;
        assertEqual(new Set(types).size, types.length, "every widget type is listed once");

        for (const entry of WidgetRegistry.entries) {
            assert(!!entry.name, entry.type + " has a display name");
            _compiles(WidgetRegistry.widgetUrl(entry.type), entry.type + " widget");
            if (entry.settings)
                _compiles(WidgetRegistry.settingsUrl(entry.type), entry.type + " settings page");
            if (entry.popup) {
                assert(!!entry.popupPanel, entry.type + " names a panel for its popup");
                _compiles(WidgetRegistry.popupPanelUrl(entry.popup), entry.type + " popup panel");
            }
        }

        assertEqual(WidgetRegistry.displayName("nonexistent"), "nonexistent", "unknown type falls back to its key");
        assertEqual(WidgetRegistry.popupContent("clock"), "calendar", "clock opens the calendar");
        assert(!WidgetRegistry.hasPopupMode("tray"), "tray manages its own popup");

        // Presets: every type whose cell takes interactions has them, for its bindings
        for (const type of WidgetRegistry.types)
            assertEqual(WidgetRegistry.hasPresets(type), type !== "tray", type + (type === "tray" ? ": no presets (each icon has its own clicks)" : ": has presets"));
        assert(WidgetRegistry.hasCellInteractions("music") && !WidgetRegistry.hasCellInteractions("workspaces") && !WidgetRegistry.hasCellInteractions("tray"),
               "cell interactions: all but the tray's and the workspaces' (their icons and buttons keep their clicks)");
        assert(WidgetRegistry.hasSettingsPage("clock") && !WidgetRegistry.hasSettingsPage("music"), "a settings page: only where one is listed");
        assert(!WidgetRegistry.hasPresets("nonexistent") && !WidgetRegistry.hasCellInteractions("nonexistent"), "an unknown type: no presets, no interactions");
        assert(WidgetRegistry.entry("constructor") === null && WidgetRegistry.entry("__proto__") === null && !WidgetRegistry.hasPresets("toString"),
               "an inherited name is no type");
        assertEqual(JSON.stringify(WidgetRegistry.declaredBindings("clock")) + JSON.stringify(WidgetRegistry.declaredBindings("nonexistent")), "{}{}",
                    "declared bindings: none for a type that declares none, nor for an unknown type");
        assertEqual(WidgetRegistry.actionIds("clock").length + WidgetRegistry.actionIds("nonexistent").length, 0, "own actions: none where none are declared");

        // The core's own actions: ids unique, a known kind, a plain one-line label; every
        // declared binding valid against them (else it would silently count as unassigned)
        for (const entry of WidgetRegistry.coreEntries) {
            const ids = WidgetRegistry.actionIds(entry.type);
            assertEqual(new Set(ids).size, ids.length, entry.type + ": its action ids are unique");
            for (const action of entry.actions ?? []) {
                assert(["run", "adjust"].includes(action.kind), entry.type + "/" + action.id + ": a known kind");
                assert(typeof action.label === "string" && action.label !== "" && !action.label.includes("\n"), entry.type + "/" + action.id + ": a label");
            }
            const declared = WidgetRegistry.declaredBindings(entry.type);
            for (const interaction of Object.keys(declared))
                assert(InteractionRules.validBinding(declared[interaction], interaction, ids), entry.type + ": its " + interaction + " binding is valid");
        }
        assertEqual(JSON.stringify(WidgetRegistry.action("sound", "volume")), JSON.stringify({ id: "volume", label: "Volume", kind: "adjust", state: false }),
                    "action: an adjust action, state false where it says none");
        assertEqual(WidgetRegistry.action("stt", "serverStart").state, true, "… one that tells its state");
        assertEqual(WidgetRegistry.action("music", "next").kind, "run", "… run");
        assert(WidgetRegistry.action("music", "bogus") === null && WidgetRegistry.action("nonexistent", "next") === null, "… none for an undeclared one");
        const copy = WidgetRegistry.action("music", "next");
        copy.kind = "adjust";
        assertEqual(WidgetRegistry.action("music", "next").kind, "run", "… a copy: a change to it changes nothing");
    }
}
