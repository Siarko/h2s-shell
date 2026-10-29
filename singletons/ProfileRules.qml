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
    // a later profile wins a conflict. Keys that are not in `defaults` are ignored: a
    // profile saved by a newer version, or a setting that was removed.
    // Returns { values, setBy: key → profile name, active: [names] }.
    function resolve(defaults, profiles, facts) {
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
        return { values: values, setBy: setBy, active: active };
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
    // so it can be edited as a profile; and Power save, on battery.
    function seedProfiles(defaults) {
        return [
            { name: "Full", enabled: true, when: {}, set: Object.assign({}, defaults) },
            { name: "Power save", enabled: true,
              when: { all: [ { fact: "power.onBattery", is: true } ] },
              set: {
                  "polling.hardware.interval": 10000,
                  "polling.hardware.gpuSampling": "single",
                  "polling.temperatures.interval": 30000,
                  "polling.disk.interval": 0,
                  "polling.network.interval": 10000,
                  "graphs.heartbeat": false,
                  "system.powerProfile": "power-saver"
              } }
        ];
    }
}
