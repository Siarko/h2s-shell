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
        assert(WidgetRegistry.hasCellInteractions("music") && WidgetRegistry.hasCellInteractions("workspaces") && !WidgetRegistry.hasCellInteractions("tray"),
               "cell interactions: all but the tray's");
        assert(WidgetRegistry.hasSettingsPage("clock") && !WidgetRegistry.hasSettingsPage("music"), "a settings page: only where one is listed");
        assert(!WidgetRegistry.hasPresets("nonexistent") && !WidgetRegistry.hasCellInteractions("nonexistent"), "an unknown type: no presets, no interactions");
        assert(WidgetRegistry.entry("constructor") === null && WidgetRegistry.entry("__proto__") === null && !WidgetRegistry.hasPresets("toString"),
               "an inherited name is no type");
        assertEqual(JSON.stringify(WidgetRegistry.declaredBindings("clock")) + JSON.stringify(WidgetRegistry.declaredBindings("nonexistent")), "{}{}",
                    "declared bindings: none yet, none for an unknown type");
        assertEqual(WidgetRegistry.actionIds("music").length + WidgetRegistry.actionIds("nonexistent").length, 0, "own actions: none yet");
    }
}
