pragma Singleton

import Quickshell
import QtQuick

// Pure functions behind Profiles: evaluating a profile's condition against the current
// facts, and layering the active profiles over the defaults. No state and no I/O, so
// tests/ProfilesTest.qml can exercise them with made-up facts.
//
// A profile:   { name, enabled, when, set }
// A condition: { all: [...] } | { any: [...] } | { not: condition }
//              | { fact, is } | { fact, lt } | { fact, gt }
//              — `is` against a list-valued fact (e.g. the open panels) means "contains"
//              — an empty or missing condition always holds.
Singleton {
    id: root

    // The facts a condition can test, for the settings editor. `type` picks the editor:
    //   bool    — { fact, is: true|false }
    //   percent — { fact, lt|gt: 0–100 }
    //   enum    — { fact, is: one of `options` }
    //   panel   — { fact, is: a popup content key } (the fact is the list of open ones)
    readonly property var factTypes: [
        { fact: "power.onBattery", label: "On battery", type: "bool" },
        { fact: "battery.percent", label: "Battery level", type: "percent" },
        { fact: "power.profile", label: "System power profile", type: "enum",
          options: ["power-saver", "balanced", "performance"] },
        { fact: "screen.locked", label: "Screen locked", type: "bool" },
        { fact: "input.tabletMode", label: "Tablet mode", type: "bool" },
        { fact: "window.fullscreen", label: "Fullscreen window", type: "bool" },
        { fact: "panel.open", label: "Popup open", type: "panel" }
    ]

    function factType(fact) {
        return factTypes.find(type => type.fact === fact) ?? null;
    }

    // The leaves of a condition the settings editor can show as a flat list, or null when
    // it is something else (nested any/not, written by hand in the config)
    function flatLeaves(condition) {
        if (!condition || Object.keys(condition).length === 0)
            return [];
        const leaves = condition.all ?? (condition.fact !== undefined ? [condition] : null);
        if (!leaves || leaves.some(leaf => leaf.fact === undefined))
            return null;
        return leaves;
    }

    // One leaf as text, e.g. "On battery", "Battery level < 20 %", "Popup open: hardware"
    function describeLeaf(leaf) {
        const type = factType(leaf.fact);
        const label = type?.label ?? leaf.fact;
        if (leaf.lt !== undefined)
            return label + " < " + leaf.lt + (type?.type === "percent" ? " %" : "");
        if (leaf.gt !== undefined)
            return label + " > " + leaf.gt + (type?.type === "percent" ? " %" : "");
        if (leaf.is === true)
            return label;
        if (leaf.is === false)
            return "Not " + label.charAt(0).toLowerCase() + label.slice(1);
        return label + ": " + leaf.is;
    }

    // A whole condition as text, for the list of profiles
    function describe(condition) {
        const leaves = flatLeaves(condition);
        if (leaves === null)
            return "Custom condition (edited in the config)";
        if (leaves.length === 0)
            return "Always";
        return leaves.map(describeLeaf).join(" and ");
    }

    function matches(condition, facts) {
        if (!condition || Object.keys(condition).length === 0)
            return true;
        if (condition.all !== undefined)
            return condition.all.every(child => matches(child, facts));
        if (condition.any !== undefined)
            return condition.any.some(child => matches(child, facts));
        if (condition.not !== undefined)
            return !matches(condition.not, facts);
        if (condition.fact === undefined)
            return false;

        const value = facts?.[condition.fact];
        // An unknown or not-yet-known fact satisfies no comparison, so a profile never
        // switches on because a fact is missing
        if (value === undefined || value === null)
            return false;
        if (condition.is !== undefined)
            return Array.isArray(value) ? value.includes(condition.is) : value === condition.is;
        if (condition.lt !== undefined)
            return value < condition.lt;
        if (condition.gt !== undefined)
            return value > condition.gt;
        return false;
    }

    // Defaults overlaid by every enabled profile whose condition holds, in list order, so
    // a later profile wins a conflict; then the global values — settings the user pinned
    // as global, which no profile changes. Keys that are not in `defaults` are ignored: a
    // profile saved by a newer version, or a setting that was removed.
    // Returns { values, setBy: key → profile name or "global", active: [names] }.
    function resolve(defaults, profiles, facts, globals) {
        const values = Object.assign({}, defaults);
        const setBy = {};
        const active = [];
        for (const profile of profiles ?? []) {
            if (profile.enabled === false || !matches(profile.when, facts))
                continue;
            active.push(profile.name);
            for (const key in profile.set ?? {}) {
                if (!(key in defaults))
                    continue;
                values[key] = profile.set[key];
                setBy[key] = profile.name;
            }
        }
        for (const key in globals ?? {}) {
            if (!(key in defaults))
                continue;
            values[key] = globals[key];
            setBy[key] = "global";
        }
        return { values: values, setBy: setBy, active: active };
    }

    // Copies settings from their place in the old config into profiles, once per key
    // (docs/plans/global-profiles.md). For every schema entry with a `legacy` location
    // whose key is not in `migratedKeys` yet: an always-global setting goes into the
    // globals, any other into Full (created at the top if the user has none) — so Full
    // spells out the user's own values. A key whose old value is undefined is only marked.
    // `readLegacy(path)` returns the old value, and throws when the path does not lead
    // anywhere — a mistake in the schema, which must not mark the key done and lose its
    // value. Inputs are not modified.
    // Returns { profiles, globals, migratedKeys, copied: [keys], failed: [key: reason] }.
    function migrateLegacy(entries, readLegacy, migratedKeys, profiles, globals) {
        const newProfiles = JSON.parse(JSON.stringify(profiles ?? []));
        const newGlobals = Object.assign({}, globals ?? {});
        const done = (migratedKeys ?? []).slice();
        const copied = [];
        const failed = [];
        for (const entry of entries) {
            if (!entry.legacy || done.includes(entry.key))
                continue;
            let oldValue;
            try {
                oldValue = readLegacy(entry.legacy);
            } catch (error) {
                failed.push(entry.key + ": " + error.message);
                continue;
            }
            done.push(entry.key);
            if (oldValue === undefined)
                continue;
            if (entry.global === true) {
                newGlobals[entry.key] = oldValue;
            } else {
                let full = newProfiles.find(profile => profile.name === "Full");
                if (!full) {
                    full = { name: "Full", enabled: true, when: {}, set: {} };
                    newProfiles.unshift(full);
                }
                full.set = full.set ?? {};
                full.set[entry.key] = oldValue;
            }
            copied.push(entry.key);
        }
        return { profiles: newProfiles, globals: newGlobals, migratedKeys: done, copied: copied, failed: failed };
    }

    // A value at its old place in a config file from before profiles, parsed from JSON:
    // `path` is e.g. ["media", "visualizerStyle"], or a function (oldConfig) => value. The
    // old widget settings were a JSON string, so a path starting at "widgetProfiles"
    // parses it. Anything missing on the way is undefined — a config written after
    // profiles simply has nothing to move.
    function readLegacy(oldConfig, path) {
        if (typeof path === "function")
            return path(oldConfig ?? {});
        let node = oldConfig;
        for (let i = 0; i < path.length; i++) {
            if (node === undefined || node === null)
                return undefined;
            node = node[path[i]];
            if (i === 0 && path[0] === "widgetProfiles") {
                try {
                    node = JSON.parse(node || "{}");
                } catch (error) {
                    return undefined;
                }
            }
        }
        return node;
    }

    // ---- the bar (docs/plans/global-profiles.md, stage 4) ----

    // A bar section from the old config's two parallel arrays — widget types, and a JSON
    // array of preset names that may be shorter (a missing name means no preset)
    function sectionFromLegacy(types, presetsJson) {
        let presets = [];
        try {
            presets = JSON.parse(presetsJson || "[]");
        } catch (error) {}
        return Array.from(types ?? []).map((type, index) => ({ type: type, preset: presets[index] || "" }));
    }

    // The preset library from the old widgetProfiles object. Keys starting with "_" were
    // per widget type, not presets: popup mode and the hardware popup are profile settings
    // now and are dropped here; the hardware capsule labels move into every hardware
    // preset, since a preset now describes its capsule completely; "_labels" was unused.
    function presetsFromWidgetProfiles(widgetProfiles) {
        const presets = {};
        for (const type in widgetProfiles ?? {}) {
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

    // Model entries for one bar section, with a key that stays the same as long as the
    // entry does: ScriptModel keeps a delegate whose key is unchanged, so editing some
    // unrelated setting does not recreate every widget on the bar
    function sectionModel(section) {
        const seen = {};
        return (section ?? []).map(entry => {
            const base = entry.type + "/" + (entry.preset ?? "");
            seen[base] = (seen[base] ?? 0) + 1;
            return { key: base + "#" + seen[base], type: entry.type, preset: entry.preset ?? "" };
        });
    }

    // What a bar section shows while it changes from `shown` to `wanted` (both
    // sectionModel lists): the wanted entries, with the shown ones that are going kept in
    // their place, marked `leaving: true`, so they can shrink away before they are dropped.
    // An entry kept after a widget before it went sits after the nearest kept one.
    function withLeaving(shown, wanted) {
        const wantedKeys = new Set((wanted ?? []).map(entry => entry.key));
        const result = (wanted ?? []).slice();
        (shown ?? []).forEach((entry, index) => {
            if (wantedKeys.has(entry.key))
                return;
            let at = 0;
            for (let i = index - 1; i >= 0; i--) {
                const position = result.findIndex(other => other.key === shown[i].key);
                if (position >= 0) {
                    at = position + 1;
                    break;
                }
            }
            result.splice(at, 0, Object.assign({}, entry, { leaving: true }));
        });
        return result;
    }

    // ---- widget presets in the bar sections ----

    readonly property var _sectionKeys: ["bar.left", "bar.center", "bar.right"]

    // Where a preset is used: [{ profile, section }] for every profile — and the pinned
    // global value, as profile "global" — whose bar section has an entry of that type
    // pointing at it. Inherited sections are counted where they are set, not again.
    function presetUsages(profiles, globals, type, name) {
        const usages = [];
        const sources = (profiles ?? []).map(profile => ({ name: profile.name, set: profile.set ?? {} }))
            .concat([{ name: "global", set: globals ?? {} }]);
        for (const source of sources) {
            for (const key of _sectionKeys) {
                if ((source.set[key] ?? []).some(entry => entry.type === type && entry.preset === name))
                    usages.push({ profile: source.name, section: key.slice(4) });
            }
        }
        return usages;
    }

    // Profiles and globals with every bar entry of `type` that points at preset `from`
    // pointed at `to` instead — "" to leave them without a preset when it is deleted.
    // Inputs are not modified. Returns { profiles, globals }.
    function replacePreset(profiles, globals, type, from, to) {
        const repoint = section => (section ?? []).map(entry =>
            entry.type === type && entry.preset === from ? { type: entry.type, preset: to } : entry);
        const newProfiles = JSON.parse(JSON.stringify(profiles ?? []));
        for (const profile of newProfiles) {
            for (const key of _sectionKeys) {
                if (profile.set?.[key] !== undefined)
                    profile.set[key] = repoint(profile.set[key]);
            }
        }
        const newGlobals = Object.assign({}, globals ?? {});
        for (const key of _sectionKeys) {
            if (newGlobals[key] !== undefined)
                newGlobals[key] = repoint(newGlobals[key]);
        }
        return { profiles: newProfiles, globals: newGlobals };
    }

    // Every fact a condition reads
    function factsRead(condition) {
        if (!condition)
            return [];
        if (condition.all !== undefined || condition.any !== undefined)
            return [].concat(...(condition.all ?? condition.any).map(factsRead));
        if (condition.not !== undefined)
            return factsRead(condition.not);
        return condition.fact !== undefined ? [condition.fact] : [];
    }

    // Why a profile cannot be saved, or "" if it can. A profile that sets the system
    // power profile while depending on it could switch itself on and off.
    function saveError(profile) {
        if (profile.set?.["system.powerProfile"] !== undefined
                && profile.set["system.powerProfile"] !== "unchanged"
                && factsRead(profile.when).includes("power.profile"))
            return "A profile that sets the system power profile cannot also depend on it — it would switch itself on and off.";
        return "";
    }

    // The profiles a config starts with: Full, always on, with every default spelled out
    // so it can be edited as a profile; and Power save, on battery. Full names the
    // system power profile in use when the config is seeded, so there is always a
    // concrete one to go back to when Power save stops applying, and seeding changes
    // nothing.
    function seedProfiles(defaults, currentPowerProfile) {
        const full = Object.assign({}, defaults);
        if (currentPowerProfile)
            full["system.powerProfile"] = currentPowerProfile;
        return [
            { name: "Full", enabled: true, when: {}, set: full },
            { name: "Power save", enabled: true,
              when: { all: [ { fact: "power.onBattery", is: true } ] },
              set: {
                  "polling.hardware.interval": 10000,
                  "polling.hardware.gpuSampling": "single",
                  "polling.temperatures.interval": 30000,
                  "polling.disk.interval": 0,
                  "polling.network.interval": 10000,
                  "graphs.heartbeat": false,
                  "polling.visualizer.fps": 15,
                  "system.powerProfile": "power-saver"
              } }
        ];
    }
}
