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
    }
}
