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

    // Settings that moved into the schema bring their value from a config file written
    // before profiles along, once — see ProfileRules.migrateLegacy. Runs after seeding, so
    // the values land in the seeded Full.
    function _migrateIfNeeded() {
        if (!Config.ready || Config.profiles === "")
            return
        const old = oldConfig()
        const result = ProfileRules.migrateLegacy(SettingsSchema.entries,
                                                  path => ProfileRules.readLegacy(old, path),
                                                  Config.migratedKeys, profiles, globals)
        for (const failure of result.failed)
            _log.error("Cannot migrate", failure)
        if (result.migratedKeys.length === Config.migratedKeys.length)
            return
        if (result.copied.length > 0) {
            backUpConfig()
            // Always shown, not only in debug: a one-time change to the user's config
            console.log("[Profiles] Moved into profiles from the old config:", result.copied.join(", "))
        }
        Config.profiles = JSON.stringify(result.profiles)
        Config.globals = JSON.stringify(result.globals)
        Config.migratedKeys = result.migratedKeys
    }

    // The config file as JSON, with the sections from before profiles that Config no
    // longer declares; read fresh for each migration
    function oldConfig() {
        _configFile.reload()
        try {
            return JSON.parse(_configFile.text() || "{}")
        } catch (error) {
            return {}
        }
    }

    function backUpConfig() {
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

    // The preset library starts as a copy of the old widget settings, once
    function _migratePresetsIfNeeded() {
        if (!Config.ready || Config.widgetPresets !== "")
            return
        let old = {}
        try {
            old = JSON.parse(oldConfig().widgetProfiles || "{}")
        } catch (error) {}
        backUpConfig()
        Config.widgetPresets = JSON.stringify(ProfileRules.presetsFromWidgetProfiles(old))
        console.log("[Profiles] Widget profiles are now widget presets")
    }

    Component.onCompleted: {
        _seedIfNeeded()
        _migrateIfNeeded()
        _migratePresetsIfNeeded()
        _applyPowerProfile()
    }

    Connections {
        target: Config
        function onReadyChanged() {
            Qt.callLater(root._seedIfNeeded)
            Qt.callLater(root._migrateIfNeeded)
            Qt.callLater(root._migratePresetsIfNeeded)
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
        Qt.callLater(_applyPowerProfile)
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

    // A setting as a profile at `index` sees it: the global value if pinned, else the
    // profile's own, else what it inherits
    function editedValue(index, key) {
        if (key in effectiveGlobals)
            return effectiveGlobals[key]
        return profiles[index]?.set?.[key] ?? inheritedValue(index, key)
    }

    // Writes a setting the way its editor would: the global value if pinned, else into
    // the profile at `index`
    function writeSetting(index, key, newValue) {
        if (key in effectiveGlobals)
            return setGlobal(key, newValue)
        return setOverride(index, key, newValue)
    }

    // Writes a setting from the shell itself (not a settings page, which edits a chosen
    // profile): where its value comes from now — the global value if pinned, else the
    // profile that sets it, else Full (which the rest build on) if it is in effect, else the
    // first profile in effect — so the change shows at once, in the profile it belongs to.
    // Never into a profile not in effect: the change would not show.
    function writeInEffect(key, newValue) {
        if (key in effectiveGlobals)
            return setGlobal(key, newValue)
        const setter = setBy(key)
        const target = setter !== "" ? setter
            : activeProfiles.includes("Full") ? "Full"
            : activeProfiles[0] ?? ""
        const index = profiles.findIndex(profile => profile.name === target)
        if (index < 0)
            return false
        return setOverride(index, key, newValue)
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
        "input.tabletMode": TabletMode.active,
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
    // For the battery popup: what the profiles want ("unchanged" when none sets it) and
    // the system's profile by name ("power-saver", "balanced", "performance")
    readonly property string wantedPowerProfile: _wantedPowerProfile
    readonly property string currentPowerProfile: _powerProfileName(PowerProfiles.profile) ?? ""

    // Sets the system's power profile by hand. It stays until the profiles next want
    // another one (above) — the battery popup's override.
    function setPowerProfile(name) {
        PowerProfiles.profile = _powerProfileValue(name);
    }

    // Deferred: setting the system profile changes the "power.profile" fact, and doing it
    // while the facts are still being re-evaluated was a binding loop on facts and
    // _resolved (seen at startup and when simulating a battery)
    on_WantedPowerProfileChanged: Qt.callLater(_applyPowerProfile)

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
