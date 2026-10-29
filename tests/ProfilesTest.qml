import QtQuick
import qs.singletons

TestCase {
    suiteName: "Profiles"

    function run() {
        // --- schema ---
        const keys = SettingsSchema.entries.map(entry => entry.key);
        assertEqual(new Set(keys).size, keys.length, "every setting key is listed once");
        for (const entry of SettingsSchema.entries) {
            assert(!!entry.label && !!entry.group && !!entry.type, entry.key + " has a label, group and type");
            if (entry.type === "enum")
                assert(entry.options.some(option => option.value === entry.default), entry.key + " default is one of its options");
        }

        // --- the system profile is the shell's behaviour before profiles ---
        // Temperatures were 5 s (CPU) and 2 s (GPU); one rate since profiles, at 2 s.
        assertEqual(Profiles.value("polling.hardware.interval"), 2000, "hardware every 2 s");
        assertEqual(Profiles.value("polling.hardware.gpuSampling"), "averaged", "GPU load averaged");
        assertEqual(Profiles.value("polling.temperatures.interval"), 2000, "temperatures every 2 s");
        assertEqual(Profiles.value("polling.disk.interval"), 10000, "disk every 10 s");
        assertEqual(Profiles.value("polling.network.interval"), 2000, "network every 2 s");
        assertEqual(SettingsSchema.keysInGroup("performance").length, 5, "all polling keys are in the performance group");

        // --- conditions ---
        const onBattery = { fact: "power.onBattery", is: true };
        const low = { fact: "battery.percent", lt: 20 };
        const facts = { "power.onBattery": true, "battery.percent": 15 };
        assert(ProfileRules.matches(undefined, facts), "no condition always holds");
        assert(ProfileRules.matches({}, facts), "an empty condition always holds");
        assert(ProfileRules.matches(onBattery, facts), "is: equal value");
        assert(!ProfileRules.matches(onBattery, { "power.onBattery": false }), "is: other value");
        assert(ProfileRules.matches(low, facts), "lt");
        assert(!ProfileRules.matches({ fact: "battery.percent", gt: 20 }, facts), "gt");
        assert(ProfileRules.matches({ all: [onBattery, low] }, facts), "all: every child holds");
        assert(!ProfileRules.matches({ all: [onBattery, low] }, { "power.onBattery": true, "battery.percent": 80 }), "all: one fails");
        assert(ProfileRules.matches({ any: [low, onBattery] }, { "power.onBattery": true, "battery.percent": 80 }), "any: one holds");
        assert(ProfileRules.matches({ not: onBattery }, { "power.onBattery": false }), "not");
        assert(ProfileRules.matches({ any: [{ all: [onBattery, low] }, { fact: "screen.locked", is: true }] },
                                    { "screen.locked": true }), "nested");
        assert(!ProfileRules.matches(low, {}), "an unknown fact satisfies nothing");
        // On purpose: "battery is not below 20 %" is true on a desktop that has no battery
        assert(ProfileRules.matches({ not: low }, {}), "not of an unknown fact holds");
        assert(!ProfileRules.matches({ fact: "power.onBattery" }, facts), "a leaf without a comparison never holds");
        assert(ProfileRules.matches({ fact: "panel.open", is: "hardware" }, { "panel.open": ["calendar", "hardware"] }), "is on a list: contains");
        assert(!ProfileRules.matches({ fact: "panel.open", is: "hardware" }, { "panel.open": [] }), "is on an empty list");

        // --- layering ---
        const defaults = { a: 1, b: 2, c: 3 };
        const profiles = [
            { name: "Base", when: {}, set: { a: 10, b: 20 } },
            { name: "Battery", when: onBattery, set: { b: 200, unknown: 9 } },
            { name: "Off", enabled: false, when: {}, set: { c: 300 } }
        ];
        const onAc = ProfileRules.resolve(defaults, profiles, { "power.onBattery": false });
        assertEqual(JSON.stringify(onAc.values), JSON.stringify({ a: 10, b: 20, c: 3 }), "only matching profiles apply");
        assertEqual(JSON.stringify(onAc.active), JSON.stringify(["Base"]), "active list");
        const battery = ProfileRules.resolve(defaults, profiles, facts);
        assertEqual(battery.values.b, 200, "a later profile wins a conflict");
        assertEqual(battery.setBy.b, "Battery", "setBy names the winner");
        assertEqual(battery.setBy.c, undefined, "a key no profile sets has no setter");
        assert(!("unknown" in battery.values), "keys outside the schema are ignored");
        assertEqual(battery.values.c, 3, "a disabled profile does not apply");
        assertEqual(JSON.stringify(ProfileRules.resolve(defaults, [], facts).values), JSON.stringify(defaults),
            "no profiles: the system profile");
        assertEqual(defaults.a, 1, "resolve does not modify the defaults");

        // --- loop guard ---
        const loops = { name: "x", when: { fact: "power.profile", is: "balanced" }, set: { "system.powerProfile": "power-saver" } };
        assert(ProfileRules.saveError(loops) !== "", "setting the power profile while depending on it is refused");
        assertEqual(ProfileRules.saveError({ name: "x", when: { not: { fact: "power.profile", is: "x" } }, set: { "system.powerProfile": "unchanged" } }), "",
            "leaving it unchanged is fine");
        assertEqual(ProfileRules.saveError({ name: "x", when: onBattery, set: { "system.powerProfile": "power-saver" } }), "",
            "setting it on another condition is fine");

        // --- seed ---
        const seed = ProfileRules.seedProfiles(SettingsSchema.defaults);
        assertEqual(JSON.stringify(seed.map(profile => profile.name)), JSON.stringify(["Full", "Power save"]), "Full and Power save");
        assertEqual(JSON.stringify(ProfileRules.resolve(SettingsSchema.defaults, seed, { "power.onBattery": false }).values),
            JSON.stringify(SettingsSchema.defaults), "on AC the seed changes nothing");
        assert(seed.every(profile => ProfileRules.saveError(profile) === ""), "the seed passes its own guard");
        for (const key in seed[1].set)
            assert(key in SettingsSchema.defaults, "Power save sets a known key: " + key);
        assertEqual(JSON.stringify(Profiles.activeProfiles), JSON.stringify(["Full"]), "on this desktop only Full is active");
    }
}
