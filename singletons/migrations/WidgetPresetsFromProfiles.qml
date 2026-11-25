import QtQuick

// The widget preset library made from the old widget settings (widgetProfiles, a JSON text
// in config.json), once: each type's named settings become its presets. Keys starting with
// "_" were per widget type, not presets: popup mode and the hardware popup became profile
// settings (PreProfilesSettings) and are dropped here; the hardware capsule labels move into
// every hardware preset, since a preset describes its capsule completely; "_labels" was
// unused. A preset already in the library stays as it is. The old widget settings stay in
// the file. Frozen as it was when this moved onto the runner.
QtObject {
    readonly property string migrationId: "1.0.0-widget-presets"
    readonly property string since: "1.0.0"
    readonly property string summary: "Widget profiles are now widget presets"
    // The part reset when it fails, in words (the failure notice lists it)
    readonly property string scopeLabel: "widget presets"
    readonly property var scope: ["read:raw:widgetProfiles", "preset:*"]

    // Older versions made the library whenever it was empty text, and only then
    function appliedBefore(config) {
        return typeof config.widgetPresets === "string" && config.widgetPresets !== "";
    }

    function _presets(widgetProfiles) {
        const presets = {};
        for (const type in widgetProfiles ?? {}) {
            // Older versions stopped at a type set to null, before writing anything
            if (widgetProfiles[type] === null)
                continue;
            const byName = {};
            for (const name in widgetProfiles[type]) {
                if (!name.startsWith("_"))
                    byName[name] = JSON.parse(JSON.stringify(widgetProfiles[type][name]));
            }
            const capsuleLabels = widgetProfiles[type]["_capsuleLabels"];
            if (type === "hardware" && capsuleLabels) {
                for (const name in byName)
                    byName[name].capsuleLabels = Object.assign({}, capsuleLabels);
            }
            if (Object.keys(byName).length > 0)
                presets[type] = byName;
        }
        return presets;
    }

    function migrate(document, context) {
        let widgetProfiles = {};
        try {
            widgetProfiles = JSON.parse(document.raw.widgetProfiles || "{}");
        } catch (error) {}
        const made = _presets(widgetProfiles);
        for (const type of Object.keys(made)) {
            const library = document.presets[type] ?? {};
            for (const name of Object.keys(made[type]))
                if (!Object.prototype.hasOwnProperty.call(library, name))
                    library[name] = made[type][name];
            document.presets[type] = library;
        }
        return document;
    }
}
