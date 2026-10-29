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
        assertEqual(Profiles.value("graphs.heartbeat"), true, "graph heartbeat on");
        assertEqual(Profiles.value("polling.visualizer.fps"), 60, "visualizer at 60 fps");
        assertEqual(SettingsSchema.keysInGroup("performance").length, 6, "polling and graph keys are in the performance group");
        assert(Profiles.isSystemGlobal("general.debug") && Profiles.isSystemGlobal("general.fetchDebug"), "debug switches are always global");

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

        // --- describing conditions for the editor ---
        assertEqual(ProfileRules.describe({}), "Always", "empty condition");
        assertEqual(ProfileRules.describe({ all: [onBattery, low] }), "On battery and Battery level < 20 %", "flat all");
        assertEqual(ProfileRules.describe(onBattery), "On battery", "a bare leaf counts as flat");
        assertEqual(ProfileRules.describeLeaf({ fact: "screen.locked", is: false }), "Not screen locked", "a false bool");
        assertEqual(ProfileRules.describeLeaf({ fact: "panel.open", is: "hardware" }), "Popup open: hardware", "a panel");
        assertEqual(ProfileRules.flatLeaves({ any: [onBattery] }), null, "any is not flat");
        assertEqual(ProfileRules.describe({ all: [{ not: onBattery }] }), "Custom condition (edited in the config)", "nested is shown as custom");

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

        // --- always-global settings (schema flag) ---
        for (const key in SettingsSchema.systemGlobalDefaults)
            assert(Profiles.isGlobal(key) && Profiles.isSystemGlobal(key), key + " is always global");
        const systemGlobals = Object.assign({}, { c: 3 }, {});
        assertEqual(ProfileRules.resolve(defaults, [{ name: "P", when: {}, set: { c: 99 } }], facts, systemGlobals).values.c, 3,
            "a profile cannot change an always-global setting");

        // --- global settings ---
        const pinned = ProfileRules.resolve(defaults, profiles, facts, { b: 7, unknown: 1 });
        assertEqual(pinned.values.b, 7, "a global value wins over every profile");
        assertEqual(pinned.setBy.b, "global", "setBy reports it as global");
        assertEqual(pinned.values.a, 10, "other keys still come from the profiles");
        assert(!("unknown" in pinned.values), "a global outside the schema is ignored");
        assertEqual(JSON.stringify(ProfileRules.resolve(defaults, profiles, facts, {}).values),
            JSON.stringify(battery.values), "no globals: as before");

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
        assertEqual(Profiles.inheritedFrom(0, "polling.hardware.interval"), "", "the first profile inherits the default");
        const seededOnPerformance = ProfileRules.seedProfiles(SettingsSchema.defaults, "performance");
        assertEqual(seededOnPerformance[0].set["system.powerProfile"], "performance",
            "Full names the power profile in use when seeding");
        assertEqual(seed[0].set["system.powerProfile"], "unchanged", "without one known, Full leaves it unchanged");

        // --- migrating the old config, once per key ---
        const legacyConfig = { media: { visualizerStyle: "bars" }, general: { debug: true } };
        const readLegacy = path => path.reduce((node, part) => node?.[part], legacyConfig);
        const legacyEntries = [
            { key: "media.style", legacy: ["media", "visualizerStyle"] },
            { key: "general.debug", legacy: ["general", "debug"], global: true },
            { key: "media.missing", legacy: ["media", "nothing"] },
            { key: "polling.x" }
        ];
        const userProfiles = [{ name: "Full", when: {}, set: { "polling.x": 1 } }, { name: "Power save", when: onBattery, set: {} }];
        const migrated = ProfileRules.migrateLegacy(legacyEntries, readLegacy, [], userProfiles, {});
        assertEqual(migrated.profiles[0].set["media.style"], "bars", "a setting moves into Full with the user's value");
        assertEqual(migrated.profiles[0].set["polling.x"], 1, "Full keeps what it had");
        assertEqual(migrated.globals["general.debug"], true, "an always-global setting moves into the globals");
        assert(!("general.debug" in migrated.profiles[0].set), "and not into Full");
        assertEqual(JSON.stringify(migrated.copied), JSON.stringify(["media.style", "general.debug"]), "copied lists what moved");
        assert(migrated.migratedKeys.includes("media.missing"), "a missing old value is still marked done");
        assert(!migrated.migratedKeys.includes("polling.x"), "keys without a legacy place are not touched");
        assertEqual(userProfiles[0].set["media.style"], undefined, "the input profiles are not modified");
        const again = ProfileRules.migrateLegacy(legacyEntries, path => "changed", migrated.migratedKeys, migrated.profiles, migrated.globals);
        assertEqual(again.copied.length, 0, "a second run copies nothing — later edits are not overwritten");
        const broken = ProfileRules.migrateLegacy([{ key: "k", legacy: ["nosection", "x"] }],
            path => { throw new Error("Config has no nosection"); }, [], userProfiles, {});
        assert(!broken.migratedKeys.includes("k"), "a wrong legacy path does not mark the key done");
        assertEqual(broken.failed.length, 1, "and is reported");
        // A config file from before profiles, shaped like the user's (no credentials)
        const oldFile = {
            general: { debug: false, fetch_debug: true },
            media: { visualizerStyle: "bars", visualizerLayout: "horizontal" },
            stt: { socketPath: "", previewEnabled: true, previewWidth: 180, finalLingerMs: 2500,
                   showPending: true, pauseMusicWhileDictating: true, debug: false },
            notifications: { codePatterns: ["\\d{4,6}"] },
            lockscreen: { screensaverEnabled: false, screensaverTimeout: 100, fadeInDuration: 200,
                          fadeOutDuration: 800, notificationsOnScreensaver: false, lockscreenEnabled: false,
                          lockscreenTimeout: 5, notificationsOnLock: true },
            gcal: { enabled: true, debug: false },
            bar: {
                content: { left: ["power", "workspaces"], leftProfiles: '["", "default"]',
                           center: ["clock"], centerProfiles: '["default"]',
                           right: ["music"], rightProfiles: "[]" },
                layout: { reservedSpace: 40, barHeight: 40, topOffset: 0, leftMargin: 0, rightMargin: 0,
                          leftPadding: 5, rightPadding: 5, radiusTopLeft: 0, radiusTopRight: 0,
                          radiusBottomLeft: 0, radiusBottomRight: 0 }
            },
            widgetProfiles: JSON.stringify({ hardware: { _popup: ["cpu"], _popupLabels: {} }, music: { _popupMode: "hover" } })
        };
        const readOld = path => ProfileRules.readLegacy(oldFile, path);
        for (const entry of SettingsSchema.entries) {
            if (!entry.legacy || entry.key.endsWith(".popupMode"))
                continue;
            assert(readOld(entry.legacy) !== undefined, entry.key + ": read from an old config file");
        }
        assertEqual(readOld(["stt", "previewWidth"]), 180, "a plain path");
        assertEqual(readOld(["widgetProfiles", "music", "_popupMode"]), "hover", "a path into the old widget JSON string");
        assertEqual(readOld(SettingsSchema.entry("widgets.music.popupMode").legacy), "hover", "popup mode from the old widget settings");
        assertEqual(readOld(SettingsSchema.entry("widgets.clock.popupMode").legacy), undefined, "no stored popup mode: nothing to move");
        assertEqual(JSON.stringify(readOld(SettingsSchema.entry("bar.left").legacy)),
            JSON.stringify([{ type: "power", preset: "" }, { type: "workspaces", preset: "default" }]), "a bar section from the old arrays");
        assertEqual(ProfileRules.readLegacy({}, ["media", "visualizerStyle"]), undefined, "a config without the section has nothing to move");
        assertEqual(ProfileRules.readLegacy({}, SettingsSchema.entry("bar.left").legacy), undefined,
            "no old bar section is no value — not an empty bar");
        const noFull = ProfileRules.migrateLegacy(legacyEntries, readLegacy, [], [{ name: "Mine", when: {}, set: {} }], {});
        assertEqual(noFull.profiles[0].name, "Full", "without Full, one is created at the top");
        assertEqual(noFull.profiles[1].name, "Mine", "and the user's profiles follow");

        // --- the bar ---
        assertEqual(JSON.stringify(ProfileRules.sectionFromLegacy(["stt", "music", "sound"], '["", "x"]')),
            JSON.stringify([{ type: "stt", preset: "" }, { type: "music", preset: "x" }, { type: "sound", preset: "" }]),
            "a section from the two old arrays, a short preset list meaning no preset");
        assertEqual(ProfileRules.sectionFromLegacy(["clock"], "not json")[0].preset, "", "broken preset JSON: no presets");
        const oldWidgets = {
            workspaces: { default: { title: "" }, only_special: { showNormal: true } },
            clock: { default: { format: "hh:mm" }, _popupMode: "click" },
            hardware: { default: { capsule: ["cpuTemp"] }, _popup: ["cpu"], _labels: {}, _capsuleLabels: { cpuTemp: "CPU" }, _popupLabels: {} },
            music: { _popupMode: "hover" }
        };
        const presets = ProfileRules.presetsFromWidgetProfiles(oldWidgets);
        assertEqual(JSON.stringify(Object.keys(presets.workspaces)), JSON.stringify(["default", "only_special"]), "presets are kept");
        assertEqual(presets.clock._popupMode, undefined, "per-type keys are not presets");
        assertEqual(presets.music, undefined, "a type with only per-type keys has no presets");
        assertEqual(presets.hardware.default.capsuleLabels.cpuTemp, "CPU", "capsule labels move into the hardware preset");
        assertEqual(JSON.stringify(presets.hardware.default.capsule), JSON.stringify(["cpuTemp"]), "with its capsule sources");
        const model = ProfileRules.sectionModel([{ type: "clock", preset: "a" }, { type: "clock", preset: "a" }, { type: "tray", preset: "" }]);
        assertEqual(JSON.stringify(model.map(entry => entry.key)), JSON.stringify(["clock/a#1", "clock/a#2", "tray/#1"]),
            "model keys are unique and depend only on the entry");

        // --- saving ---
        assert(Config.readOnly, "the test run cannot write the user's config");
        const refused = Profiles.save([loops]);
        assert(refused.startsWith("x: "), "save refuses a profile that fails the guard, naming it");
    }
}
