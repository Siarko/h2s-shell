pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// Effective values of the settings in SettingsSchema: the system profile (the schema
// defaults) overlaid by every active profile, in order. Read them with value(key) in a
// binding; it follows profile changes. See docs/plans/adaptive-polling.md.
//
// Step 3 of the plan: real facts; the profiles are still the seed list, not yet from
// the config.
Singleton {
    id: root

    property var profiles: ProfileRules.seedProfiles(SettingsSchema.defaults)

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
