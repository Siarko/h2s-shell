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
//              "bool", "string", "stringList"; or a structured value with its own editor
//              on its page ("barSection", "hardwarePopup"), overridden as a whole
//   default  — value of the system profile
//   min/max  — for interval, number and slider
//   suffix   — unit shown after a number or slider, e.g. "s"
//   neutral  — for slider: the resting value inside the range, which its fill starts from
//              (0 on a speed that can go either way); unset, the fill starts at min
//   hint     — a short explanation shown under the setting
//   options  — for enum: [{ value, label }]
//   optionsFrom — for enum: where the options come from at run time instead
//              ("iconThemes": the installed icon themes, IconThemes)
//   presentation — for enum: "dropdown" for a list to pick from instead of pills
//   global   — true for a setting that is never per profile (debug switches, say): it
//              behaves as if the user had pinned it as global, and cannot be unpinned
//   legacy   — where the setting lived in the old config, e.g. ["media", "visualizerStyle"],
//              or a function (config) => value where it was spread over several places;
//              its value there is copied into the profiles once (ProfileRules.migrateLegacy)
Singleton {
    id: root

    // Old widget settings, for the legacy readers of the bar entries below; `config` is
    // the parsed config file from before profiles
    function _oldWidgetSettings(config) {
        try {
            return JSON.parse(config.widgetProfiles || "{}");
        } catch (error) {
            return {};
        }
    }


    function _sectionEntry(side, label, defaultTypes) {
        return { key: "bar." + side, label: label, group: "barContent", type: "barSection",
                 default: defaultTypes.map(type => ({ type: type, preset: "" })),
                 // No old section is no value, not an empty bar
                 legacy: config => config.bar?.content?.[side] === undefined ? undefined
                     : ProfileRules.sectionFromLegacy(config.bar.content[side],
                                                      config.bar.content[side + "Profiles"]) };
    }

    // Popup mode per widget type that opens a popup (WidgetRegistry), click by default:
    // hover cannot fire on a touch screen
    readonly property var _popupModeEntries: WidgetRegistry.entries.filter(widget => widget.popup).map(widget => ({
        key: "widgets." + widget.type + ".popupMode", label: widget.name + " popup", group: "popupMode",
        type: "enum", default: WidgetRegistry.defaultPopupMode,
        legacy: config => root._oldWidgetSettings(config)[widget.type]?.["_popupMode"],
        options: [
            { value: "click", label: "Click" },
            { value: "hover", label: "Hover" },
            { value: "none", label: "None" }
        ]
    }))

    readonly property var entries: _baseEntries.concat(_popupModeEntries)

    readonly property var _baseEntries: [
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
              // Glow: the waveform's shape as light, reaching out as far as each band;
              // even glow: the same light, all bands at the bass's level
              { value: "glow", label: "Glow" },
              { value: "glowEven", label: "Even glow" },
              { value: "none", label: "None" }
          ] },
        { key: "media.visualizerLayout", label: "Layout", group: "media",
          type: "enum", default: "horizontal", legacy: ["media", "visualizerLayout"], options: [
              // Centred: mirrored about a middle line, below the controls or down each
              // side; bottom and sides: glued to the popup's edges, growing inward
              { value: "horizontal", label: "Horizontal (centered)" },
              { value: "horizontalBottom", label: "Horizontal (bottom)" },
              { value: "vertical", label: "Vertical (centered)" },
              { value: "verticalSides", label: "Vertical (sides)" },
              { value: "around", label: "Around cover" }
          ] },
        // Around the cover: two or three colours read from the cover, instead of the theme's
        { key: "media.coverColors", label: "Colours from the cover", group: "media",
          type: "bool", default: false,
          hint: "Around cover: the visualiser in the cover's own colours" },
        // 0 square, 100 a circle; 33 is the 20 px it always had on the 120 px cover
        { key: "media.coverRounding", label: "Cover rounding", group: "media",
          type: "slider", min: 0, max: 100, suffix: "%", default: 33 },
        // Degrees a second, clockwise; below 0 the other way. While playing; never with
        // reduced motion
        { key: "media.coverRotation", label: "Cover rotation", group: "media",
          type: "slider", min: -360, max: 360, neutral: 0, suffix: "°/s", default: 0 },

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
        { key: "lockscreen.screensaverCommands", label: "Run commands when the screensaver starts and ends",
          group: "lockscreen", type: "bool", default: false, legacy: ["lockscreen", "screensaverExecCmd"],
          hint: "They follow your idle time, not the screensaver's visibility: locking the screen does not end it, coming back to the lock prompt does." },
        { key: "lockscreen.screensaverStartCommand", label: "When the screensaver starts", group: "lockscreen",
          type: "string", default: "", legacy: ["lockscreen", "screensaverExecSleep"],
          hint: "Run with sh -c, detached from the shell" },
        { key: "lockscreen.screensaverEndCommand", label: "When you come back", group: "lockscreen",
          type: "string", default: "", legacy: ["lockscreen", "screensaverExecWakeup"] },
        { key: "lockscreen.screensaverNotificationDetail", label: "Notifications on the screensaver show",
          group: "lockscreen", type: "enum", default: "full", options: [
              { value: "full", label: "In full" },
              { value: "title", label: "Title only" },
              { value: "app", label: "App only" }
          ] },
        { key: "lockscreen.lockscreenEnabled", label: "Enable lock screen", group: "lockscreen",
          type: "bool", default: false, legacy: ["lockscreen", "lockscreenEnabled"] },
        { key: "lockscreen.lockscreenTimeout", label: "Lock after", group: "lockscreen",
          type: "number", min: 5, max: 86400, suffix: "s", default: 300,
          legacy: ["lockscreen", "lockscreenTimeout"] },
        { key: "lockscreen.notificationsOnLock", label: "Show notifications on lock screen",
          group: "lockscreen", type: "bool", default: true,
          legacy: ["lockscreen", "notificationsOnLock"] },
        { key: "lockscreen.lockNotificationDetail", label: "Notifications on the lock screen show",
          group: "lockscreen", type: "enum", default: "full", options: [
              { value: "full", label: "In full" },
              { value: "title", label: "Title only" },
              { value: "app", label: "App only" }
          ] },

        // ── Notifications ──
        // Regular expressions for one-time codes in incoming notifications
        { key: "notifications.codePatterns", label: "Code patterns", group: "notifications",
          type: "stringList", default: ["\\d{4,8}"], legacy: ["notifications", "codePatterns"] },

        // ── Dictation ──
        { key: "stt.previewEnabled", label: "Show recognized text", group: "stt",
          type: "bool", default: true, legacy: ["stt", "previewEnabled"] },
        { key: "stt.previewWidth", label: "Preview width", group: "stt",
          type: "slider", min: 0, max: 600, suffix: "px", default: 180, legacy: ["stt", "previewWidth"],
          hint: "How far the widget slides open while dictation is running. At rest it collapses back to just the microphone icon." },
        { key: "stt.finalLingerMs", label: "Keep typed text visible for", group: "stt",
          type: "number", min: 0, max: 600000, suffix: "ms", default: 2500, legacy: ["stt", "finalLingerMs"] },
        { key: "stt.showPending", label: "Show pending fragment counter", group: "stt",
          type: "bool", default: true, legacy: ["stt", "showPending"] },
        { key: "stt.pauseMusicWhileDictating", label: "Pause music while dictating", group: "stt",
          type: "bool", default: true, legacy: ["stt", "pauseMusicWhileDictating"],
          hint: "Speaker output reaches the microphone and gets transcribed. Only a pause the shell applied is resumed afterwards." },
        // Machine wiring, not a mode: a profile switch would drop the dictation connection
        { key: "stt.socketPath", label: "Socket path", group: "stt",
          type: "string", default: "", global: true, legacy: ["stt", "socketPath"],
          hint: "Leave empty to use $XDG_RUNTIME_DIR/ptt/ctl.sock" },
        { key: "stt.debug", label: "Debug log", group: "stt",
          type: "bool", default: false, global: true, legacy: ["stt", "debug"] },

        // ── Calendar ── (the account, tokens and chosen calendars stay in Config.gcal)
        { key: "gcal.enabled", label: "Enable Google Calendar", group: "calendar",
          type: "bool", default: true, legacy: ["gcal", "enabled"] },
        { key: "gcal.debug", label: "Debug Mode", group: "calendar",
          type: "bool", default: false, global: true, legacy: ["gcal", "debug"] },

        // ── Bar ──
        _sectionEntry("left", "Left section", ["power", "settings", "workspaces"]),
        _sectionEntry("center", "Center section", ["clock"]),
        _sectionEntry("right", "Right section", ["music", "sound", "bluetooth", "tray", "network", "notifications"]),
        // Which sources the hardware popup lists (null: all) and their labels; the
        // capsule on the bar is described by its preset instead
        { key: "widgets.hardware.popup", label: "Hardware popup", group: "hardwarePopup",
          type: "hardwarePopup", default: { sources: null, labels: {} },
          legacy: config => {
              const hardware = root._oldWidgetSettings(config)["hardware"] ?? {};
              if (hardware["_popup"] === undefined && hardware["_popupLabels"] === undefined)
                  return undefined;
              return { sources: hardware["_popup"] ?? null, labels: hardware["_popupLabels"] ?? {} };
          } },

        // Toasts: new notifications sliding in at the top right of the screen
        { key: "notifications.toasts", label: "Show toasts", group: "notifications",
          type: "bool", default: true,
          hint: "Off, notifications only go to the notification panel." },
        { key: "notifications.toastDuration", label: "Show each toast for", group: "notifications",
          type: "number", min: 1, max: 120, suffix: "s", default: 5 },
        { key: "notifications.toastLayout", label: "Several at once", group: "notifications",
          type: "enum", default: "queue", options: [
              { value: "queue", label: "One at a time, the rest counted" },
              { value: "column", label: "A column" }
          ] },
        { key: "notifications.toastColumnSize", label: "Toasts in the column", group: "notifications",
          type: "number", min: 2, max: 10, default: 3,
          hint: "More wait in the queue, counted beside the column." },

        // ── Appearance ── the look itself is in the theme; the profile picks which
        { key: "appearance.theme", label: "Theme", group: "appearance",
          type: "string", default: "default", suggestions: "themes",
          hint: "A file in ~/.config/h2s_shell/themes/, without .json. \"default\" without a file is the built-in look." },
        { key: "appearance.iconTheme", label: "Icon theme", group: "appearance",
          type: "enum", default: "", global: true, optionsFrom: "iconThemes", presentation: "dropdown",
          hint: "Automatic is the system's icon theme if installed, else the first one found. Applies when the shell restarts." },
        { key: "animation.speed", label: "Animation speed", group: "appearance",
          type: "slider", min: 25, max: 400, suffix: "%", default: 100,
          hint: "200% is twice as fast. How each animation moves is up to the theme." },
        { key: "animation.reduceMotion", label: "Reduce motion", group: "appearance",
          type: "bool", default: false,
          hint: "Things move into place at once and indicators stop pulsing; colours and fades still change smoothly." },

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
