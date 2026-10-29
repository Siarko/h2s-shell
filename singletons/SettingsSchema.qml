pragma Singleton

import Quickshell
import QtQuick

// The settings a profile can override, with their types and defaults. The defaults
// together are the read-only system profile (see docs/plans/adaptive-polling.md): what
// applies to a key that no active profile sets.
//
// Entry fields:
//   key      — dotted name, as stored in a profile's `set`
//   label    — shown in settings
//   group    — settings section the key is edited in
//   type     — "interval" (ms, 0 = paused), "number" (a field), "slider", "enum",
//              "bool", "string", "stringList"
//   default  — value of the system profile
//   min/max  — for interval, number and slider
//   suffix   — unit shown after a number or slider, e.g. "s"
//   options  — for enum: [{ value, label }]
//   global   — true for a setting that is never per profile (debug switches, say): it
//              behaves as if the user had pinned it as global, and cannot be unpinned
//   legacy   — where the setting lived in the old config, e.g. ["media", "visualizerStyle"];
//              its value there is copied into the profiles once (ProfileRules.migrateLegacy)
Singleton {
    id: root

    readonly property var entries: [
        // ── General ──
        { key: "general.debug", label: "Debug Mode", group: "general",
          type: "bool", default: false, global: true, legacy: ["general", "debug"] },
        { key: "general.fetchDebug", label: "Debug Mode | Fetch", group: "general",
          type: "bool", default: false, global: true, legacy: ["general", "fetch_debug"] },

        // ── Media ──
        { key: "media.visualizerStyle", label: "Visualizer style", group: "media",
          type: "enum", default: "waveform", legacy: ["media", "visualizerStyle"], options: [
              { value: "waveform", label: "Waveform" },
              { value: "bars", label: "Bars" },
              { value: "dots", label: "Dots" },
              { value: "none", label: "None" }
          ] },
        { key: "media.visualizerLayout", label: "Layout", group: "media",
          type: "enum", default: "horizontal", legacy: ["media", "visualizerLayout"], options: [
              { value: "horizontal", label: "Horizontal" },
              { value: "vertical", label: "Vertical" }
          ] },

        // ── Lockscreen ──
        { key: "lockscreen.screensaverEnabled", label: "Enable screensaver", group: "lockscreen",
          type: "bool", default: false, legacy: ["lockscreen", "screensaverEnabled"] },
        { key: "lockscreen.screensaverTimeout", label: "Activate after", group: "lockscreen",
          type: "number", min: 5, max: 86400, suffix: "s", default: 300,
          legacy: ["lockscreen", "screensaverTimeout"] },
        { key: "lockscreen.fadeInDuration", label: "Fade in", group: "lockscreen",
          type: "slider", min: 100, max: 2000, suffix: "ms", default: 800,
          legacy: ["lockscreen", "fadeInDuration"] },
        { key: "lockscreen.fadeOutDuration", label: "Fade out", group: "lockscreen",
          type: "slider", min: 100, max: 2000, suffix: "ms", default: 400,
          legacy: ["lockscreen", "fadeOutDuration"] },
        { key: "lockscreen.notificationsOnScreensaver", label: "Show notifications on screensaver",
          group: "lockscreen", type: "bool", default: true,
          legacy: ["lockscreen", "notificationsOnScreensaver"] },
        { key: "lockscreen.lockscreenEnabled", label: "Enable lock screen", group: "lockscreen",
          type: "bool", default: false, legacy: ["lockscreen", "lockscreenEnabled"] },
        { key: "lockscreen.lockscreenTimeout", label: "Lock after", group: "lockscreen",
          type: "number", min: 5, max: 86400, suffix: "s", default: 300,
          legacy: ["lockscreen", "lockscreenTimeout"] },
        { key: "lockscreen.notificationsOnLock", label: "Show notifications on lock screen",
          group: "lockscreen", type: "bool", default: true,
          legacy: ["lockscreen", "notificationsOnLock"] },

        // ── Notifications ──
        // Regular expressions for one-time codes in incoming notifications
        { key: "notifications.codePatterns", label: "Code patterns", group: "notifications",
          type: "stringList", default: ["\\d{4,8}"], legacy: ["notifications", "codePatterns"] },

        // ── Performance ──
        { key: "polling.hardware.interval", label: "Hardware", group: "performance",
          type: "interval", min: 0, max: 600000, default: 2000 },
        { key: "polling.hardware.gpuSampling", label: "GPU load sampling", group: "performance",
          type: "enum", default: "averaged", options: [
              { value: "averaged", label: "Averaged (5 samples/s)" },
              { value: "single", label: "One sample per update" }
          ] },
        { key: "polling.temperatures.interval", label: "Temperatures", group: "performance",
          type: "interval", min: 0, max: 600000, default: 2000 },
        { key: "polling.disk.interval", label: "Disk", group: "performance",
          type: "interval", min: 0, max: 600000, default: 10000 },
        { key: "polling.network.interval", label: "Network throughput", group: "performance",
          type: "interval", min: 0, max: 600000, default: 2000 },
        // cava's frame rate for the music visualizer; written into the generated cava
        // config (scripts/cava.ini is the template)
        { key: "polling.visualizer.fps", label: "Visualizer frame rate", group: "media",
          type: "enum", default: 60, options: [
              { value: 15, label: "15 fps" },
              { value: 30, label: "30 fps" },
              { value: 60, label: "60 fps" }
          ] },
        // A brief wave across every history graph when it takes a sample
        { key: "graphs.heartbeat", label: "Graph heartbeat", group: "performance",
          type: "bool", default: true },
        // Applied by Profiles while a profile sets it (step 6 of the plan); "unchanged"
        // leaves the system's own choice alone
        { key: "system.powerProfile", label: "System power profile", group: "power",
          type: "enum", default: "unchanged", options: [
              { value: "unchanged", label: "Leave unchanged" },
              { value: "power-saver", label: "Power saver" },
              { value: "balanced", label: "Balanced" },
              { value: "performance", label: "Performance" }
          ] }
    ]

    readonly property var _byKey: {
        let map = {};
        for (const entry of entries)
            map[entry.key] = entry;
        return map;
    }

    readonly property var defaults: {
        let values = {};
        for (const entry of entries)
            values[entry.key] = entry.default;
        return values;
    }

    // Defaults of the settings that are always global, { key: default }
    readonly property var systemGlobalDefaults: {
        let values = {};
        for (const entry of entries) {
            if (entry.global === true)
                values[entry.key] = entry.default;
        }
        return values;
    }

    function entry(key) {
        return _byKey[key] ?? null;
    }

    function keysInGroup(group) {
        return entries.filter(entry => entry.group === group).map(entry => entry.key);
    }
}
