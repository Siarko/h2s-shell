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
    readonly property var coreDefaults: ({
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

    // The core's, plus each loaded module widget's presetDefaults (its manifest), plus each
    // type's binding keys ("on.<interaction>", InteractionRules.bindingDefaults): its
    // declared bindings and what its popup implies. The popup's follows the active profile's
    // widgets.<type>.popupMode, until bindings take its place.
    readonly property var defaults: {
        const merged = ModuleMergeRules.mergePresetDefaults(coreDefaults, WidgetRegistry.entries.filter(entry => entry.module));
        const result = {};
        for (const type of Object.keys(merged))
            result[type] = merged[type];
        for (const entry of WidgetRegistry.entries) {
            if (!WidgetRegistry.hasCellInteractions(entry.type))
                continue;
            const popupMode = entry.popup ? (Profiles.value("widgets." + entry.type + ".popupMode") ?? WidgetRegistry.defaultPopupMode) : "";
            const bindings = InteractionRules.bindingDefaults(WidgetRegistry.declaredBindings(entry.type), !!entry.popup, popupMode, WidgetRegistry.actionIds(entry.type));
            if (Object.keys(bindings).length > 0)
                result[entry.type] = Object.assign({}, _own(result, entry.type) ?? {}, bindings);
        }
        return result;
    }

    // What a bar entry's interactions run: interaction => resolved binding
    // (InteractionRules), from its preset's binding keys, each falling back to the type's
    // default; a key failing its shape check counts as not set. null for a type whose cell
    // takes no interactions. Call in a binding: it follows edits.
    function bindingLookup(type, name) {
        if (!WidgetRegistry.hasCellInteractions(type))
            return null;
        return InteractionRules.presetLookup(stored(type, name), _own(defaults, type) ?? {}, WidgetRegistry.actionIds(type));
    }

    // Every preset binding key that fails its shape check, [{ type, name, key }], for the
    // widget types the registry knows
    readonly property var bindingProblems: {
        const found = [];
        for (const type of Object.keys(all)) {
            if (WidgetRegistry.entry(type) === null || !WidgetRegistry.hasCellInteractions(type))
                continue;
            const presets = _own(all, type);
            for (const name of Object.keys(presets ?? {}))
                for (const key of InteractionRules.bindingProblems(_own(presets, name), WidgetRegistry.actionIds(type)))
                    found.push({ type: type, name: name, key: key });
        }
        return found;
    }
    // The problems already logged, as text: one line when one appears, again only after it
    // went
    property var _loggedProblems: []
    // How many such lines were logged (read by the tests)
    property int problemLinesLogged: 0
    onBindingProblemsChanged: _logProblems()
    Component.onCompleted: _logProblems()

    function _logProblems() {
        const now = bindingProblems.map(problem => JSON.stringify([problem.type, problem.name, problem.key]));
        bindingProblems.forEach((problem, index) => {
            if (_loggedProblems.includes(now[index]))
                return;
            problemLinesLogged++;
            console.warn("[WidgetPresets] " + WidgetRegistry.displayName(problem.type) + " preset " + JSON.stringify(problem.name)
                         + ": " + problem.key + " is not a valid binding, its default is used");
        });
        _loggedProblems = now;
    }

    function names(type) {
        return Object.keys(all[type] ?? {});
    }

    // Own properties only: a name like "__proto__" or "constructor" must never reach the
    // object's prototype (library[type]["__proto__"] is Object.prototype, which "exists")
    function _own(object, key) {
        return object !== null && typeof object === "object" && Object.prototype.hasOwnProperty.call(object, key) ? object[key] : undefined;
    }

    // A name a preset may have: not empty, never "__proto__" (setting it would set a prototype)
    function validName(name) {
        return typeof name === "string" && name !== "" && name !== "__proto__";
    }

    function exists(type, name) {
        return validName(name) && _own(_own(all, type), name) !== undefined;
    }

    // The keys a preset itself sets (a copy; {} when it does not exist)
    function stored(type, name) {
        const preset = validName(name) ? _own(_own(all, type), name) : undefined;
        return preset !== null && typeof preset === "object" ? JSON.parse(JSON.stringify(preset)) : {};
    }

    // A key of a preset, or the type's default. Call in a binding: it follows edits.
    function value(type, name, key) {
        const stored = validName(name) ? _own(_own(_own(all, type), name), key) : undefined;
        return stored !== undefined ? stored : _own(_own(defaults, type), key);
    }

    // Writes a key; undefined removes it, so it falls back to the default again
    function set(type, name, key, newValue) {
        if (!validName(name) || key === "__proto__" || type === "__proto__")
            return;
        const library = JSON.parse(JSON.stringify(all));
        library[type] = _own(library, type) ?? {};
        library[type][name] = _own(library[type], name) ?? {};
        if (newValue === undefined)
            delete library[type][name][key];
        else
            library[type][name][key] = newValue;
        Config.widgetPresets = JSON.stringify(library);
    }

    // An empty preset, so a new name exists as soon as it is given
    function create(type, name) {
        if (!validName(name) || type === "__proto__" || exists(type, name))
            return;
        const library = JSON.parse(JSON.stringify(all));
        library[type] = _own(library, type) ?? {};
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
