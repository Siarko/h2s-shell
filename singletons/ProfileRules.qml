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
