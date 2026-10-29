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

    // Settings moving into the schema bring their old value along once — see
    // ProfileRules.migrateLegacy. Runs after seeding, so the values land in the seeded Full.
    function _migrateIfNeeded() {
        if (!Config.ready || Config.profiles === "")
            return
        const result = ProfileRules.migrateLegacy(SettingsSchema.entries, _readLegacy,
                                                  Config.migratedKeys, profiles, globals)
        for (const failure of result.failed)
            _log.error("Cannot migrate", failure)
        if (result.migratedKeys.length === Config.migratedKeys.length)
            return
        if (result.copied.length > 0) {
            _backUpConfig()
            // Always shown, not only in debug: a one-time change to the user's config
            console.log("[Profiles] Moved into profiles from the old config:", result.copied.join(", "))
        }
        Config.profiles = JSON.stringify(result.profiles)
        Config.globals = JSON.stringify(result.globals)
        Config.migratedKeys = result.migratedKeys
    }

    // A value at its old place in Config, e.g. ["media", "visualizerStyle"]; the old
    // widget settings were a JSON string, so a path starting at "widgetProfiles" parses it.
    // Throws when a section on the way does not exist: the path itself is wrong.
    function _readLegacy(path) {
        let node = Config
        for (let i = 0; i < path.length; i++) {
            if (node === undefined || node === null)
                return undefined
            if (i < path.length - 1 && node[path[i]] === undefined)
                throw new Error("Config has no " + path.slice(0, i + 1).join("."))
            node = node[path[i]]
            if (i === 0 && path[0] === "widgetProfiles")
                node = JSON.parse(node || "{}")
        }
        // QML list properties come back as list objects; store a plain array
        return node !== null && typeof node === "object" && node.length !== undefined && !Array.isArray(node)
            ? Array.from(node) : node
    }

    function _backUpConfig() {
        if (Config.readOnly)
            return
        const stamp = new Date().toISOString().replace(/[:.]/g, "-")
        _configCopy.path = Config.path + ".bak-" + stamp
        _configCopy.setText(_configFile.text())
    }

    FileView {
        id: _configFile
        path: Config.path
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: _configCopy
        blockWrites: true
        // Only ever written, to a new file
        printErrors: false
    }

    Component.onCompleted: {
        _seedIfNeeded()
        _migrateIfNeeded()
        _applyPowerProfile()
    }

    Connections {
        target: Config
        function onReadyChanged() {
            Qt.callLater(root._seedIfNeeded)
            Qt.callLater(root._migrateIfNeeded)
        }
        function onProfilesChanged() { Qt.callLater(root._migrateIfNeeded) }
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
        // Set here rather than inherited from the debug setting, which Profiles itself
        // provides; only error() is used, and that always prints
        enabled: false
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

    // ---- editing, for the settings pages ----
    // Each edit saves the whole list through save(); a refusal lands in lastError.
    property string lastError: ""

    function _copy() {
        return JSON.parse(JSON.stringify(profiles))
    }

    function _commit(list) {
        lastError = save(list)
        return lastError === ""
    }

    // What a key would be at a profile's place in the list if that profile did not set
    // it: the defaults overlaid by the active profiles above it
    function inheritedValue(index, key) {
        return ProfileRules.resolve(SettingsSchema.defaults, profiles.slice(0, index), facts).values[key]
    }

    // Where that inherited value comes from: the name of the active profile above that
    // sets it, or "" for the default
    function inheritedFrom(index, key) {
        return ProfileRules.resolve(SettingsSchema.defaults, profiles.slice(0, index), facts).setBy[key] ?? ""
    }

    function isGlobal(key) {
        return key in effectiveGlobals
    }

    // Always global by the schema, not by the user's choice
    function isSystemGlobal(key) {
        return SettingsSchema.entry(key)?.global === true
    }

    // Pinning keeps what applies now, so nothing visibly changes. The profiles' own values
    // for the key are kept, just ignored, and come back when it is unpinned.
    function pinGlobal(key) {
        const pinned = Object.assign({}, globals)
        pinned[key] = value(key)
        Config.globals = JSON.stringify(pinned)
    }

    function unpinGlobal(key) {
        if (isSystemGlobal(key))
            return
        const pinned = Object.assign({}, globals)
        delete pinned[key]
        Config.globals = JSON.stringify(pinned)
    }

    function setGlobal(key, newValue) {
        const pinned = Object.assign({}, globals)
        pinned[key] = newValue
        Config.globals = JSON.stringify(pinned)
    }

    function setOverride(index, key, newValue) {
        const list = _copy()
        list[index].set = list[index].set ?? {}
        list[index].set[key] = newValue
        return _commit(list)
    }

    function clearOverride(index, key) {
        const list = _copy()
        delete list[index].set?.[key]
        return _commit(list)
    }

    // changes: any of { name, enabled, when }
    function updateProfile(index, changes) {
        const list = _copy()
        Object.assign(list[index], changes)
        return _commit(list)
    }

    function addProfile() {
        const list = _copy()
        let number = list.length + 1
        while (list.some(profile => profile.name === "Profile " + number))
            number++
        list.push({ name: "Profile " + number, enabled: true, when: {}, set: {} })
        return _commit(list)
    }

    function removeProfile(index) {
        const list = _copy()
        list.splice(index, 1)
        return _commit(list)
    }

    // Later profiles win, so moving one down raises its priority
    function moveProfile(index, delta) {
        const target = index + delta
        if (target < 0 || target >= profiles.length)
            return false
        const list = _copy()
        const [moved] = list.splice(index, 1)
        list.splice(target, 0, moved)
        return _commit(list)
    }

    // Reported by Lockscreen, which reads its settings from here: reading Lockscreen.locked
    // instead would make the two singletons depend on each other
    property bool screenLocked: false

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
        "screen.locked": root.screenLocked,
        "window.fullscreen": Hyprland.monitors.values.some(monitor => monitor.activeWorkspace?.hasFullscreen ?? false),
        "panel.open": Object.keys(root._openPanels)
    })

    readonly property var facts: Object.assign({}, realFacts, simulated)

    // Settings pinned as global: { key: value }
    readonly property var globals: {
        try {
            const parsed = JSON.parse(Config.globals || "{}")
            return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
        } catch (error) {
            return {}
        }
    }

    // Pinned by the user, plus the settings the schema marks as always global — at their
    // stored value once edited, else their default — so no profile can change them
    readonly property var effectiveGlobals: Object.assign({}, SettingsSchema.systemGlobalDefaults, globals)

    readonly property var _resolved: ProfileRules.resolve(SettingsSchema.defaults, profiles, facts, effectiveGlobals)

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
                globals: root.globals,
                values: root.effective
            }, null, 2);
        }
    }
}
