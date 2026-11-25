import QtQuick

// Settings from a config written before profiles (1.0.0), copied from their old places in
// config.json into the profiles, once per key. A key the user pinned for every profile goes
// into the globals, any other into the profile named Full — seeded with the defaults before
// this runs, so Full then spells out the user's own values (it overwrites what Full holds).
// Each key copied, or found with nothing at its old place, gets its own marker (the key
// itself in migratedKeys), as older versions wrote them: a key already marked is left alone,
// so a value set since stays, and an older shell reading the result does not copy it again.
// A key whose old place cannot be read, or that has no Full to go into, stays unmarked and
// uncopied. The old sections stay in the file.
//
// The table is frozen: the keys, their old places and which are pinned, as they were when
// this moved onto the runner. The popup mode of every widget type in the old widget settings
// is copied, a module's type too (no module needs to be loaded): the core's widget types with
// a popup are named here, a type the core does not have is taken as a module's popup widget.
QtObject {
    readonly property string migrationId: "1.0.0-legacy-settings"
    readonly property string since: "1.0.0"
    readonly property string summary: "Settings from before profiles moved into the profiles"
    // The part reset when it fails, in words (the failure notice lists it)
    readonly property string scopeLabel: "settings from before profiles"
    // Full must exist: it runs once the profiles are seeded
    readonly property string phase: "afterSeed"
    readonly property string overwritesReason: "Full and the globals hold the defaults seeded before it runs; the old value is the user's choice"
    // What it writes (the keys of the table: a failure resets only those), and the old
    // sections it only reads
    readonly property var scope: _paths.map(entry => "setting:" + entry.key).concat([
        "setting:bar.left", "setting:bar.center", "setting:bar.right", "setting:widgets.hardware.popup",
        "setting:widgets.*.popupMode",
        "read:raw:general", "read:raw:media", "read:raw:lockscreen", "read:raw:notifications", "read:raw:stt",
        "read:raw:gcal", "read:raw:bar", "read:raw:widgetProfiles"])

    // Keys whose old place is a plain path; `global`: pinned for every profile
    readonly property var _paths: [
        { key: "general.debug", path: ["general", "debug"], global: true },
        { key: "general.fetchDebug", path: ["general", "fetch_debug"], global: true },
        { key: "media.visualizerStyle", path: ["media", "visualizerStyle"] },
        { key: "media.visualizerLayout", path: ["media", "visualizerLayout"] },
        { key: "lockscreen.screensaverEnabled", path: ["lockscreen", "screensaverEnabled"] },
        { key: "lockscreen.screensaverTimeout", path: ["lockscreen", "screensaverTimeout"] },
        { key: "lockscreen.fadeInDuration", path: ["lockscreen", "fadeInDuration"] },
        { key: "lockscreen.fadeOutDuration", path: ["lockscreen", "fadeOutDuration"] },
        { key: "lockscreen.notificationsOnScreensaver", path: ["lockscreen", "notificationsOnScreensaver"] },
        { key: "lockscreen.lockscreenEnabled", path: ["lockscreen", "lockscreenEnabled"] },
        { key: "lockscreen.notificationsOnLock", path: ["lockscreen", "notificationsOnLock"] },
        { key: "notifications.codePatterns", path: ["notifications", "codePatterns"] },
        { key: "stt.previewEnabled", path: ["stt", "previewEnabled"] },
        { key: "stt.previewWidth", path: ["stt", "previewWidth"] },
        { key: "stt.finalLingerMs", path: ["stt", "finalLingerMs"] },
        { key: "stt.showPending", path: ["stt", "showPending"] },
        { key: "stt.pauseMusicWhileDictating", path: ["stt", "pauseMusicWhileDictating"] },
        { key: "stt.socketPath", path: ["stt", "socketPath"], global: true },
        { key: "stt.debug", path: ["stt", "debug"], global: true },
        { key: "gcal.enabled", path: ["gcal", "enabled"] },
        { key: "gcal.debug", path: ["gcal", "debug"], global: true }
    ]
    // The core's widget types, and those of them with a popup (in the order they were listed)
    readonly property var _coreTypes: ["power", "settings", "workspaces", "clock", "music", "sound", "bluetooth",
                                       "tray", "network", "notifications", "hardware", "battery", "stt"]
    readonly property var _corePopupTypes: ["power", "clock", "music", "sound", "bluetooth", "network",
                                            "notifications", "hardware", "battery"]

    function _popupModeKey(type) {
        return "widgets." + type + ".popupMode";
    }

    // The old widget settings: a JSON text in the old config
    function _oldWidgets(raw) {
        try {
            const parsed = JSON.parse(raw.widgetProfiles || "{}");
            return parsed !== null && typeof parsed === "object" ? parsed : {};
        } catch (error) {
            return {};
        }
    }

    // The module widget types the old widget settings hold a popup mode for
    function _moduleTypes(raw) {
        const widgets = _oldWidgets(raw);
        return Object.keys(widgets).filter(type => /^[A-Za-z0-9_-]+$/.test(type) && !_coreTypes.includes(type)
                                           && widgets[type] !== null && typeof widgets[type] === "object"
                                           && widgets[type]["_popupMode"] !== undefined);
    }

    // A bar section from the old config's two parallel arrays — widget types, and a JSON
    // array of preset names that may be shorter (a missing name means no preset). No old
    // section is no value, not an empty bar.
    function _section(raw, side) {
        const content = raw.bar?.content;
        if (content?.[side] === undefined)
            return undefined;
        let presets = [];
        try {
            presets = JSON.parse(content[side + "Profiles"] || "[]");
        } catch (error) {}
        return Array.from(content[side] ?? []).map((type, index) => ({ type: type, preset: presets[index] || "" }));
    }

    // Every key of the table, in order: { key, global, read(raw) → the old value or undefined }
    function _table(raw) {
        const table = _paths.map(entry => ({ key: entry.key, global: entry.global === true,
                                             read: old => entry.path.reduce((node, part) => node === undefined || node === null ? undefined : node[part], old) }));
        for (const side of ["left", "center", "right"])
            table.push({ key: "bar." + side, global: false, read: old => _section(old, side) });
        table.push({ key: "widgets.hardware.popup", global: false, read: old => {
            const hardware = _oldWidgets(old)["hardware"] ?? {};
            if (hardware["_popup"] === undefined && hardware["_popupLabels"] === undefined)
                return undefined;
            return { sources: hardware["_popup"] ?? null, labels: hardware["_popupLabels"] ?? {} };
        } });
        for (const type of _corePopupTypes.concat(_moduleTypes(raw)))
            table.push({ key: _popupModeKey(type), global: false, read: old => _oldWidgets(old)[type]?.["_popupMode"] });
        return table;
    }

    function ownsRecord(entry) {
        return _paths.some(path => path.key === entry) || ["bar.left", "bar.center", "bar.right", "widgets.hardware.popup"].includes(entry)
            || /^widgets\.[A-Za-z0-9_-]+\.popupMode$/.test(entry);
    }

    // Every key of the table marked already
    function appliedBefore(config) {
        const marked = Array.isArray(config.migratedKeys) ? config.migratedKeys : [];
        return _table(config).every(entry => marked.includes(entry.key));
    }

    function migrate(document, context) {
        const records = document.records;
        const full = document.profiles.find(profile => profile.name === "Full");
        for (const entry of _table(document.raw)) {
            if (records.includes(entry.key))
                continue;
            let value;
            try {
                value = entry.read(document.raw);
            } catch (error) {
                continue;
            }
            if (value !== undefined) {
                if (entry.global) {
                    document.globals[entry.key] = value;
                } else if (full) {
                    full.set = full.set ?? {};
                    full.set[entry.key] = value;
                } else {
                    continue;
                }
            }
            records.push(entry.key);
        }
        return document;
    }
}
