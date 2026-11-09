pragma Singleton

import Quickshell
import QtQuick

// The widget preset library, Config.widgetPresets: named sets of one widget type's
// settings, { type: { name: { key: value } } }, shared by every bar entry and every
// shell profile that points at them. The one place that parses it, writes it, and knows
// each type's defaults — widgets and their settings pages read through here.
Singleton {
    id: root

    readonly property var all: {
        try {
            return JSON.parse(Config.widgetPresets || "{}");
        } catch (error) {
            return {};
        }
    }

    // What a preset key is when the preset does not set it, or when an entry has no
    // preset at all. stt has none: its keys fall back to the Dictation profile settings.
    readonly property var defaults: ({
        "clock": { format: "hh:mm:ss" },
        "workspaces": { title: "", showSpecial: true, showNormal: true, nameMap: [] },
        "hardware": { capsule: ["cpu"], capsuleLabels: {} },
        // The count on the bell; how the bell rings: "off", "once" (each new one),
        // "untilOpened", "untilCleared"
        "notifications": { badge: true, animation: "once" },
        // The percentage "left", "right" or "none" of the icon; colour thresholds
        // [{ value, color }] — none: the icon keeps the text colour; a colour while plugged
        // in ("" — the thresholds, as on battery)
        "battery": { percent: "right", thresholds: [], chargingColor: "" }
    })

    function names(type) {
        return Object.keys(all[type] ?? {});
    }

    function exists(type, name) {
        return name !== "" && (all[type] ?? {})[name] !== undefined;
    }

    // A key of a preset, or the type's default. Call in a binding: it follows edits.
    function value(type, name, key) {
        const stored = name !== "" ? all[type]?.[name]?.[key] : undefined;
        return stored !== undefined ? stored : defaults[type]?.[key];
    }

    // Writes a key; undefined removes it, so it falls back to the default again
    function set(type, name, key, newValue) {
        if (name === "")
            return;
        const library = JSON.parse(JSON.stringify(all));
        library[type] = library[type] ?? {};
        library[type][name] = library[type][name] ?? {};
        if (newValue === undefined)
            delete library[type][name][key];
        else
            library[type][name][key] = newValue;
        Config.widgetPresets = JSON.stringify(library);
    }

    // An empty preset, so a new name exists as soon as it is given
    function create(type, name) {
        if (name === "" || exists(type, name))
            return;
        const library = JSON.parse(JSON.stringify(all));
        library[type] = library[type] ?? {};
        library[type][name] = {};
        Config.widgetPresets = JSON.stringify(library);
    }

    // A name not used yet, e.g. "Clock 2"
    function freeName(type) {
        const base = WidgetRegistry.displayName(type);
        let number = 1;
        while (exists(type, base + " " + number))
            number++;
        return base + " " + number;
    }

    // Where it is used, [{ profile, section }] — see ProfileRules.presetUsages
    function usages(type, name) {
        return ProfileRules.presetUsages(Profiles.profiles, Profiles.globals, type, name);
    }

    // Renames it and repoints every bar entry in every profile; false if the new name is
    // taken or empty
    function rename(type, from, to) {
        if (to === "" || to === from || exists(type, to) || !exists(type, from))
            return false;
        const library = JSON.parse(JSON.stringify(all));
        library[type][to] = library[type][from];
        delete library[type][from];
        _repoint(type, from, to);
        Config.widgetPresets = JSON.stringify(library);
        return true;
    }

    // Deletes it; the bar entries that used it are left without a preset
    function remove(type, name) {
        if (!exists(type, name))
            return;
        const library = JSON.parse(JSON.stringify(all));
        delete library[type][name];
        if (Object.keys(library[type]).length === 0)
            delete library[type];
        _repoint(type, name, "");
        Config.widgetPresets = JSON.stringify(library);
    }

    function _repoint(type, from, to) {
        const result = ProfileRules.replacePreset(Profiles.profiles, Profiles.globals, type, from, to);
        Profiles.save(result.profiles);
        Config.globals = JSON.stringify(result.globals);
    }
}
