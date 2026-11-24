import QtQuick
import Quickshell
import Quickshell.Io
import qs.singletons

TestCase {
    suiteName: "Profiles"

    function run() {
        // --- reading the config: a failure is told apart from a config not made yet ---
        assert(!ProfileRules.profilesBroken("") && !ProfileRules.profilesBroken("[]") && !ProfileRules.profilesBroken("[{\"name\":\"Full\"}]"),
               "profiles not seeded yet, or a list: not broken");
        assert(ProfileRules.profilesBroken("{") && ProfileRules.profilesBroken("{}") && ProfileRules.profilesBroken("null") && ProfileRules.profilesBroken("3"),
               "profiles that are not a JSON list: broken");
        assert(!ProfileRules.configReadFailed("missing", "") && !ProfileRules.configReadFailed("", "") && !ProfileRules.configReadFailed("", "  \n"),
               "no config file yet, or an empty one: not a failure (the defaults are the user's)");
        assert(!ProfileRules.configReadFailed("", "{\"profiles\": \"[]\"}"), "a JSON object: read");
        assert(ProfileRules.configSaveAllowed(false, false), "save: a file that was read, outside the test runners: written");
        assert(!ProfileRules.configSaveAllowed(false, true), "save: a file that could not be read: never written over with the defaults");
        assert(!ProfileRules.configSaveAllowed(true, false) && !ProfileRules.configSaveAllowed(true, true), "save: the test runners: never");
        assert(!ProfileRules.configSaveAllowed(undefined, undefined), "save: nothing known: not written");
        assert(ProfileRules.configReadFailed("error", "") && ProfileRules.configReadFailed("", "{\"profiles\": ")
               && ProfileRules.configReadFailed("", "[]") && ProfileRules.configReadFailed("", "null") && ProfileRules.configReadFailed("", "\"x\""),
               "a file that could not be read, or is not a JSON object: failed");
        assertEqual(Profiles.configFailed, false, "the suites' config reads");

        // --- schema ---
        const keys = SettingsSchema.entries.map(entry => entry.key);
        assertEqual(new Set(keys).size, keys.length, "every setting key is listed once");
        for (const entry of SettingsSchema.entries) {
            assert(!!entry.label && !!entry.group && !!entry.type, entry.key + " has a label, group and type");
            // Options worked out at runtime (optionsFrom, the icon themes) have no default to check
            if (entry.type === "enum" && entry.options)
                assert(entry.options.some(option => option.value === entry.default), entry.key + " default is one of its options");
            // An info icon with nothing to say would be an empty tooltip
            if ("info" in entry)
                assert(typeof entry.info === "string" && entry.info.trim() !== "", entry.key + " info is a text");
        }
        assert(SettingsSchema.entries.some(entry => entry.info !== undefined), "an entry has an info text (the resident hide)");

        _numberRanges();

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
        assert(ProfileRules.matches({ not: low }, {}), "not of an unknown core fact holds");
        // A module's fact not known (its module absent, off, or not loaded yet): neither it nor
        // its negation holds — a `not` profile no longer switches on at every start
        const connected = { fact: "tailscale.connected", is: true };
        assert(!ProfileRules.matches(connected, {}), "an unknown module fact: does not hold");
        assert(!ProfileRules.matches({ not: connected }, {}), "… nor does its not");
        assert(!ProfileRules.matches({ not: { not: connected } }, {}), "… nor not-not");
        assertEqual(ProfileRules.evaluate({ not: connected }, {}), null, "evaluate: unknown");
        assert(!ProfileRules.matches({ fact: "tailscale.connected", is: false }, { "tailscale.connected": null }), "null is unknown too");
        assert(ProfileRules.matches({ not: connected }, { "tailscale.connected": false }), "known false: its not holds");
        assert(ProfileRules.matches({ any: [connected, onBattery] }, facts), "any: a true child wins over an unknown one");
        assert(!ProfileRules.matches({ any: [connected, { fact: "power.onBattery", is: false }] }, facts), "any: unknown and false — does not hold");
        assert(!ProfileRules.matches({ not: { any: [connected, { fact: "power.onBattery", is: false }] } }, facts), "… nor its not");
        assert(ProfileRules.matches({ not: { all: [connected, { fact: "power.onBattery", is: false }] } }, facts), "all: a false child decides, so its not holds");
        assert(!ProfileRules.matches({ all: [connected, onBattery] }, facts), "all: unknown and true — does not hold");
        assertEqual(ProfileRules.describeLeaf({ fact: "nosuch.thing", is: true }), "nosuch.thing (module not installed)", "an undeclared fact named as a module's not installed");
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
                          lockscreenTimeout: 5, notificationsOnLock: true,
                          screensaverExecCmd: false, screensaverExecSleep: "", screensaverExecWakeup: "" },
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

        // --- a default that changed (formerDefault), once ---
        const detailKey = "lockscreen.lockNotificationDetail";
        assertEqual(SettingsSchema.defaults[detailKey], "app", "the lock screen shows notifications' app only by default");
        assertEqual(SettingsSchema.entry(detailKey).formerDefault, "full", "it used to be in full");
        const seededBefore = [{ name: "Full", when: {}, set: { [detailKey]: "full", "polling.x": 1 } },
                              { name: "Mine", when: onBattery, set: { [detailKey]: "full" } }];
        const moved = ProfileRules.migrateDefaults(SettingsSchema.entries, [], seededBefore);
        assert(!(detailKey in moved.profiles[0].set), "a Full still holding the old default loses it");
        assertEqual(ProfileRules.resolve(SettingsSchema.defaults, moved.profiles, { "power.onBattery": false }).values[detailKey],
            "app", "so the new default applies");
        assertEqual(moved.profiles[0].set["polling.x"], 1, "Full keeps the rest");
        assertEqual(moved.profiles[1].set[detailKey], "full", "another profile setting it keeps it: the user's");
        assertEqual(JSON.stringify(moved.changed), JSON.stringify([detailKey]), "changed lists it");
        assert(moved.migratedKeys.includes("default:" + detailKey), "and it is marked done");
        assertEqual(seededBefore[0].set[detailKey], "full", "the input is not modified");
        const chosen = ProfileRules.migrateDefaults(SettingsSchema.entries, [],
            [{ name: "Full", when: {}, set: { [detailKey]: "title" } }]);
        assertEqual(chosen.profiles[0].set[detailKey], "title", "a value the user chose stays");
        assertEqual(chosen.changed.length, 0, "and nothing is reported");
        const notSet = ProfileRules.migrateDefaults(SettingsSchema.entries, [], [{ name: "Full", when: {}, set: {} }]);
        assertEqual(ProfileRules.resolve(SettingsSchema.defaults, notSet.profiles, {}).values[detailKey], "app",
            "a config that never held the setting gets the new default");
        const later = ProfileRules.migrateDefaults(SettingsSchema.entries, moved.migratedKeys,
            [{ name: "Full", when: {}, set: { [detailKey]: "full" } }]);
        assertEqual(later.profiles[0].set[detailKey], "full", "once done, \"full\" set again later is the user's and stays");
        assertEqual(ProfileRules.seedProfiles(SettingsSchema.defaults)[0].set[detailKey], "app", "a new config is seeded with the new default");

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
        const entry = key => ({ key: key, type: key, preset: "" });
        const changing = ProfileRules.withLeaving([entry("a"), entry("b"), entry("c"), entry("d")], [entry("a"), entry("e"), entry("d")]);
        assertEqual(changing.map(item => item.key + (item.leaving ? "-" : "")).join(" "), "a b- c- e d",
            "widgets going keep their place, after the nearest one staying");
        assertEqual(ProfileRules.withLeaving([entry("b"), entry("a")], [entry("a")]).map(item => item.key + (item.leaving ? "-" : "")).join(" "),
            "b- a", "one going from the start stays at the start");
        assertEqual(ProfileRules.withLeaving([entry("a"), { key: "b", leaving: true }], [entry("a"), entry("b")]).map(item => item.key + (item.leaving ? "-" : "")).join(" "),
            "a b", "a widget coming back is no longer going");

        // --- preset usages, renaming and deleting ---
        const withPresets = [
            { name: "Full", set: { "bar.left": [{ type: "clock", preset: "a" }, { type: "tray", preset: "" }],
                                   "bar.right": [{ type: "clock", preset: "b" }] } },
            { name: "Power save", set: { "bar.left": [{ type: "clock", preset: "a" }] } },
            { name: "Quiet", set: {} }
        ];
        const pinnedCenter = { "bar.center": [{ type: "clock", preset: "a" }] };
        assertEqual(JSON.stringify(ProfileRules.presetUsages(withPresets, pinnedCenter, "clock", "a")),
            JSON.stringify([{ profile: "Full", section: "left" }, { profile: "Power save", section: "left" },
                            { profile: "global", section: "center" }]),
            "a preset is used in every profile section that points at it, and in a pinned section");
        assertEqual(ProfileRules.presetUsages(withPresets, {}, "workspaces", "a").length, 0, "the same name of another type is not it");
        const renamed = ProfileRules.replacePreset(withPresets, pinnedCenter, "clock", "a", "c");
        assertEqual(renamed.profiles[0].set["bar.left"][0].preset, "c", "renaming repoints the entries");
        assertEqual(renamed.profiles[0].set["bar.right"][0].preset, "b", "other presets stay");
        assertEqual(renamed.globals["bar.center"][0].preset, "c", "a pinned section is repointed too");
        assertEqual(renamed.profiles[2].set["bar.left"], undefined, "a profile that inherits its sections stays inheriting");
        assertEqual(withPresets[0].set["bar.left"][0].preset, "a", "the inputs are not modified");
        assertEqual(ProfileRules.replacePreset(withPresets, {}, "clock", "a", "").profiles[1].set["bar.left"][0].preset, "",
            "deleting leaves the entries without a preset");

        // --- a removed module's settings ---
        const modProfiles = [{ name: "Full", set: { "mod.weather.city": "Oslo", "mod.weatherx.city": "Rome", "bar.left": [] } },
                             { name: "Night", set: { "mod.weather.units": "c" } }];
        const dropped = ProfileRules.withoutPrefix(modProfiles, { "mod.weather.loud": true, "general.debug": false }, "mod.weather.");
        assertEqual(JSON.stringify(dropped.profiles.map(profile => Object.keys(profile.set))), JSON.stringify([["mod.weatherx.city", "bar.left"], []]),
                    "withoutPrefix: the module's values go from every profile, another module's with a longer id stay");
        assertEqual(JSON.stringify(dropped.globals) + " " + dropped.removed, "{\"general.debug\":false} 3", "… and from the globals; counted");
        assertEqual(modProfiles[0].set["mod.weather.city"], "Oslo", "… the inputs are not modified");
        assertEqual(ProfileRules.withoutPrefix(modProfiles, {}, "bar.").removed + ProfileRules.withoutPrefix(modProfiles, {}, "mod.").removed
                    + ProfileRules.withoutPrefix(modProfiles, {}, "").removed + ProfileRules.withoutPrefix(null, null, null).removed, 0,
                    "… only a module's own prefix: core settings never go this way");

        // --- the preset library ---
        assertEqual(WidgetPresets.value("clock", "", "format"), "hh:mm:ss", "no preset: the type's default");
        assertEqual(WidgetPresets.value("clock", "no such preset", "format"), "hh:mm:ss", "a missing preset: the default");
        assertEqual(WidgetPresets.value("stt", "", "previewWidth"), undefined, "stt has no defaults — it inherits the profile setting");
        assert(WidgetRegistry.hasPresets("clock") && !WidgetRegistry.hasPresets("music"), "only widgets with a settings page have presets");
        assert(WidgetRegistry.allowsMultiple("clock") && !WidgetRegistry.allowsMultiple("tray"), "clocks may repeat in a section, the tray not");

        // --- saving ---
        assert(Config.readOnly, "the test run cannot write the user's config");
        const refused = Profiles.save([loops]);
        assert(refused.startsWith("x: "), "save refuses a profile that fails the guard, naming it");

        _oldConfigReadFresh();
    }

    property GlobalsPin _globalsPin: GlobalsPin {}

    // A number setting is used within its schema's range whatever the config file holds; the
    // file keeps what the user wrote (ProfileRules.checkedNumber, withinRanges)
    function _numberRanges() {
        const entry = { key: "system.rememberAdminMinutes", type: "number", min: 1, max: 60, default: 5 };
        const check = stored => ProfileRules.checkedNumber(entry, stored);
        assertEqual(JSON.stringify(check(30)), JSON.stringify({ value: 30, corrected: false, note: "" }), "within the range: as stored");
        assert(check(1).value === 1 && !check(1).corrected && check(60).value === 60 && !check(60).corrected, "on a bound: as stored");
        assertEqual(JSON.stringify(check(0)), JSON.stringify({ value: 1, corrected: true, note: "Set to 0 in the config file, below the minimum 1: 1 is used" }),
                    "below the minimum: the minimum, said");
        assertEqual(JSON.stringify(check(120)), JSON.stringify({ value: 60, corrected: true, note: "Set to 120 in the config file, above the maximum 60: 60 is used" }),
                    "above the maximum: the maximum, said");
        assertEqual(JSON.stringify(check("30")), JSON.stringify({ value: 5, corrected: true, note: "Set to \"30\" in the config file, not a number: the default 5 is used" }),
                    "a string: the default, said");
        assert(check(NaN).value === 5 && check(NaN).corrected && check(Infinity).value === 5 && check(null).value === 5
               && check(true).value === 5 && check([3]).value === 5 && check({}).value === 5, "NaN, infinity, null, a bool, a list, an object: the default");
        assertEqual(check(undefined).value, undefined, "missing: nothing to correct");
        assert(!check(undefined).corrected && check(undefined).note === "", "… and nothing said");
        assertEqual(check("x".repeat(100)).note.length, "Set to  in the config file, not a number: the default 5 is used".length + 40,
                    "a long stored text: capped in the note");
        assert(!/\n/.test(check("a\nb").note), "… and on one line");
        assertEqual(ProfileRules.checkedNumber({ type: "slider", min: -360, max: 360, default: 0 }, -400).value, -360, "a slider: within its range");
        assertEqual(ProfileRules.checkedNumber({ type: "interval", min: 0, max: 600000, default: 2000 }, -1).value, 0, "an interval: within its range");
        assertEqual(ProfileRules.checkedNumber({ type: "number", default: 3 }, 1e9).value, 1e9, "no min or max: any number");
        assertEqual(ProfileRules.checkedNumber({ type: "number", min: 2, default: 3 }, 1).value, 2, "only a min: kept to it");
        assertEqual(JSON.stringify(check(2.4)), JSON.stringify({ value: 2, corrected: true, note: "Set to 2.4 in the config file, not a whole number: 2 is used" }),
                    "a number field holding a fraction: rounded, said");
        assertEqual(check(0.4).value, 1, "… a fraction below the minimum: the minimum");
        assertEqual(ProfileRules.checkedNumber({ type: "slider", min: 0, max: 5, default: 2 }, 2.5).value, 2.5, "a slider: a fraction as stored");
        assertEqual(ProfileRules.checkedNumber({ type: "enum", default: 60 }, "x").value, "x", "another type: not touched");
        assertEqual(ProfileRules.checkedNumber(null, 120).value, 120, "a key without an entry: not touched");

        const entries = [entry, { key: "a.text", type: "string", default: "" }, { key: "a.gone", type: "slider", min: 0, max: 1, default: 0 }];
        const values = { "system.rememberAdminMinutes": 120, "a.text": 7 };
        const result = ProfileRules.withinRanges(entries, values);
        assertEqual(JSON.stringify(result.values), JSON.stringify({ "system.rememberAdminMinutes": 60, "a.text": 7 }), "withinRanges: numbers corrected, the rest as given");
        assertEqual(JSON.stringify(result.corrections.map(each => [each.key, each.stored, each.used])), JSON.stringify([["system.rememberAdminMinutes", 120, 60]]),
                    "… each correction listed with what was stored and what is used");
        assertEqual(values["system.rememberAdminMinutes"], 120, "… the input left as it was");

        // Told once per stored value (ProfileRules.rangeReport)
        const told = (reported, list) => ProfileRules.rangeReport(reported, list);
        const at120 = { key: "k", stored: 120, used: 60, note: "n" };
        let report = told({}, [at120]);
        assertEqual(report.toLog.length, 1, "a new correction: told");
        report = told(report.reported, [at120]);
        assertEqual(report.toLog.length, 0, "the same stored value again (another profile change): not told again");
        report = told(report.reported, [{ key: "k", stored: 0, used: 1, note: "n" }]);
        assertEqual(report.toLog.length, 1, "another stored value: told");
        report = told(told(report.reported, []).reported, [{ key: "k", stored: 0, used: 1, note: "n" }]);
        assertEqual(report.toLog.length, 1, "fine in between, then the same value again: told again");

        // The startup banner (ProfileRules.rangeNotice)
        assert(!ProfileRules.rangeNotice([]).shown, "the banner: nothing corrected, none");
        const notice = ProfileRules.rangeNotice([at120, { key: "b", stored: "x", used: 1, note: "n" }]);
        assert(notice.shown && notice.title === "Settings outside their range in the config file", "… one shown, with its title");
        assertEqual(notice.body, "k, b: the nearest allowed value is used instead, or the default where it is not a number. "
                    + "The config file is left as it is; Settings shows each with a note.", "… naming the settings");
        assert(ProfileRules.rangeNotice([{ key: "k", stored: 0 }]).key !== ProfileRules.rangeNotice([at120]).key, "… another stored value: another banner");
        assert(ProfileRules.rangeNotice(Array.from({ length: 7 }, (each, i) => ({ key: "k" + i, stored: 0 }))).body.startsWith("k0, k1, k2, k3, k4 and 2 more:"),
               "… many: five named, the rest counted");

        // Every number setting of the schema, the modules' included: its default within its range
        for (const each of SettingsSchema.entries) {
            if (ProfileRules.numberTypes.includes(each.type))
                assert(!ProfileRules.checkedNumber(each, each.default).corrected, each.key + ": its default is a number within its range");
        }
        assertEqual(Profiles.rangeCorrections.length, 0, "the suites' config: nothing corrected");

        // Through Profiles.value, the one place every reader goes through
        const before = Profiles.value("system.rememberAdminMinutes");
        try {
            _globalsPin.use({ "system.rememberAdminMinutes": 0 });
            assertEqual(Profiles.value("system.rememberAdminMinutes"), 1, "Profiles.value: stored below the minimum, the minimum");
            const logged = Profiles.rangeWarningsLogged;
            _globalsPin.use({ "system.rememberAdminMinutes": 120 });
            assertEqual(Profiles.value("system.rememberAdminMinutes"), 60, "… above the maximum, the maximum");
            assertEqual(Profiles.rangeWarningsLogged, logged + 1, "… one warning logged");
            _globalsPin.use({ "graphs.heartbeat": !Profiles.value("graphs.heartbeat") });
            assertEqual(Profiles.rangeWarningsLogged, logged + 1, "… another setting changed: not logged again");
            _globalsPin.use({ "system.rememberAdminMinutes": "ten" });
            assertEqual(Profiles.value("system.rememberAdminMinutes"), 5, "… not a number, the default");
            assertEqual(JSON.stringify(Profiles.rangeCorrections.map(each => each.key)), JSON.stringify(["system.rememberAdminMinutes"]), "… listed as corrected");
            assertEqual(JSON.parse(Config.globals)["system.rememberAdminMinutes"], "ten", "… the stored value left as the user wrote it");
        } finally {
            _globalsPin.restore();
        }
        assertEqual(Profiles.value("system.rememberAdminMinutes"), before, "put back: as before");
    }

    // The migrations read the config file fresh each time (Profiles.oldConfig): a section
    // written to the file after the first read is seen. The file is put back as it was; one
    // that was not there is removed again (until then it is empty, which every reader takes
    // as no file).
    property FileView _configOnDisk: FileView {
        blockAllReads: true
        blockWrites: true
        printErrors: false
    }

    function _oldConfigReadFresh() {
        _configOnDisk.path = Config.path;
        _configOnDisk.reload();
        const before = _configOnDisk.text() ?? "";
        const existed = _configOnDisk.loaded;
        let parsed = {};
        try {
            parsed = JSON.parse(before || "{}");
        } catch (error) {
            fail("the suites' config file is not JSON");
            return;
        }
        Profiles.oldConfig();
        parsed.legacyProbe = { layout: "probe" };
        _configOnDisk.setText(JSON.stringify(parsed));
        try {
            assertEqual(Profiles.oldConfig().legacyProbe?.layout, "probe",
                        "the old config: read fresh, a section written after the first read seen");
        } finally {
            _configOnDisk.setText(before);
        }
        assertEqual(Profiles.oldConfig().legacyProbe, undefined, "the old config: the file put back");
        if (!existed)
            Quickshell.execDetached(["rm", "-f", "--", Config.path]);
    }
}
