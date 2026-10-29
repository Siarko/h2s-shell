pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import qs.components

// Effective values of the settings in SettingsSchema: the system profile (the schema
// defaults) overlaid by every active profile, in order. Read them with value(key) in a
// binding; it follows profile changes. See docs/plans/adaptive-polling.md.
//
// The profiles live in Config.profiles. A config from before profiles has none and is
// seeded with Full and Power save; an empty list is the user's choice and leaves only
// the system profile.
Singleton {
    id: root

    readonly property var profiles: _parse(Config.profiles)

    // Seeded once the config has been read — before that, Config.profiles is "" for every
    // config, not just the ones without profiles. Not a binding: writing Config.profiles
    // from a handler of a binding on it is a binding loop.
    function _seedIfNeeded() {
        if (Config.ready && _powerProfilesKnown && Config.profiles === "")
            Config.profiles = JSON.stringify(ProfileRules.seedProfiles(SettingsSchema.defaults,
                                                                        _powerProfileName(PowerProfiles.profile)))
    }

    Component.onCompleted: {
        _seedIfNeeded()
        _applyPowerProfile()
    }

    Connections {
        target: Config
        function onReadyChanged() { Qt.callLater(root._seedIfNeeded) }
    }

    // PowerProfiles reads the daemon over D-Bus after startup; until then it reports
    // "balanced" with no performance profile. Seeding Full with that, or applying a
    // profile against it, would switch a machine that is on performance. Known after the
    // first change signal, or after a second if the real value equals the startup one.
    property bool _powerProfilesKnown: false
    on_PowerProfilesKnownChanged: {
        Qt.callLater(_seedIfNeeded)
        _applyPowerProfile()
    }

    Connections {
        target: PowerProfiles
        function onProfileChanged() { root._powerProfilesKnown = true }
        function onHasPerformanceProfileChanged() { root._powerProfilesKnown = true }
    }

    Timer {
        interval: 1000
        running: !root._powerProfilesKnown
        onTriggered: root._powerProfilesKnown = true
    }

    Logger {
        id: _log
        prefix: "[Profiles]"
    }

    function _parse(json) {
        if (json === "")
            return ProfileRules.seedProfiles(SettingsSchema.defaults)
        try {
            const parsed = JSON.parse(json)
            if (Array.isArray(parsed))
                return parsed
        } catch (error) {}
        // A broken list is not overwritten, so the user can still fix it by hand
        _log.error("Config.profiles is not a JSON array; using only the system profile")
        return []
    }

    // Replaces the profile list, unless one of them fails ProfileRules.saveError; returns
    // that error, or "" once saved
    function save(newProfiles) {
        for (const profile of newProfiles) {
            const error = ProfileRules.saveError(profile)
            if (error !== "")
                return profile.name + ": " + error
        }
        Config.profiles = JSON.stringify(newProfiles)
        return ""
    }

    // Popup content types currently open on any screen, with a count each, reported by
    // Popup.qml — several screens can show the same one
    property var _openPanels: ({})

    // Fact overrides for testing without the hardware, e.g. a battery on the desktop.
    // Set through IPC (below), never saved.
    property var simulated: ({})

    readonly property var realFacts: ({
        "power.onBattery": UPower.onBattery,
        // Unknown on a machine without a battery, so a battery condition never matches
        // there. Quickshell gives percentage as 0–1. (Not yet checked on a real battery.)
        "battery.percent": UPower.displayDevice.isPresent
            ? Math.round(UPower.displayDevice.percentage * 100) : null,
        "power.profile": root._powerProfileName(PowerProfiles.profile),
        "screen.locked": Lockscreen.locked,
        "window.fullscreen": Hyprland.monitors.values.some(monitor => monitor.activeWorkspace?.hasFullscreen ?? false),
        "panel.open": Object.keys(root._openPanels)
    })

    readonly property var facts: Object.assign({}, realFacts, simulated)

    readonly property var _resolved: ProfileRules.resolve(SettingsSchema.defaults, profiles, facts)

    readonly property var effective: _resolved.values
    // Names of the profiles in effect, in order
    readonly property var activeProfiles: _resolved.active

    function value(key) {
        return effective[key];
    }

    // The profile that set a key's current value, or "" for the system default
    function setBy(key) {
        return _resolved.setBy[key] ?? "";
    }

    function panelOpened(contentType) {
        const panels = Object.assign({}, _openPanels);
        panels[contentType] = (panels[contentType] ?? 0) + 1;
        _openPanels = panels;
    }

    function panelClosed(contentType) {
        const panels = Object.assign({}, _openPanels);
        if (--panels[contentType] <= 0)
            delete panels[contentType];
        _openPanels = panels;
    }

    // ---- system.powerProfile ----
    // Follows from the profiles and the current conditions, nothing else: whenever the
    // effective value changes to a concrete profile, the system is set to it; "unchanged"
    // leaves the system alone. Nothing is remembered or restored — coming back from
    // battery, the profile that applies on AC (Full) names the one to use. A change by
    // hand stays until the effective value next changes; the shell does not fight it.
    readonly property string _wantedPowerProfile: value("system.powerProfile") ?? "unchanged"

    on_WantedPowerProfileChanged: _applyPowerProfile()

    function _applyPowerProfile() {
        if (!_powerProfilesKnown || _wantedPowerProfile === "unchanged")
            return
        if (_wantedPowerProfile === "performance" && !PowerProfiles.hasPerformanceProfile)
            return
        if (_powerProfileName(PowerProfiles.profile) !== _wantedPowerProfile)
            PowerProfiles.profile = _powerProfileValue(_wantedPowerProfile)
    }

    function _powerProfileValue(name) {
        switch (name) {
        case "power-saver": return PowerProfile.PowerSaver;
        case "performance": return PowerProfile.Performance;
        }
        return PowerProfile.Balanced;
    }

    function _powerProfileName(profile) {
        switch (profile) {
        case PowerProfile.PowerSaver: return "power-saver";
        case PowerProfile.Balanced: return "balanced";
        case PowerProfile.Performance: return "performance";
        }
        return null;
    }

    // qs ipc call profiles simulate '{"power.onBattery": true, "battery.percent": 15}'
    // qs ipc call profiles clearSimulation
    // qs ipc call profiles status
    IpcHandler {
        target: "profiles"

        function simulate(factsJson: string): string {
            root.simulated = JSON.parse(factsJson);
            return status();
        }

        function clearSimulation(): string {
            root.simulated = {};
            return status();
        }

        function status(): string {
            return JSON.stringify({
                active: root.activeProfiles,
                facts: root.facts,
                simulated: root.simulated,
                values: root.effective
            }, null, 2);
        }
    }
}
