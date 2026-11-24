pragma Singleton

import Quickshell
import Quickshell.Io
import QtCore
import QtQuick
import qs.components

// The config file. Settings are not here: they live in the profiles (see Profiles and
// SettingsSchema). What is left is data that is not a
// preference — the Google account and its tokens, remembered per-app volumes — plus the
// widget preset library and the profiles themselves.
//
// A config written before profiles has its settings in sections this file no longer
// declares; Profiles reads those from the raw file to migrate them. Saving keeps every
// top-level key the file holds that is not declared here (JsonConfigFile), so what a newer
// shell wrote survives this one; such a config also gets a warning (newerNotice), never a
// refusal.
Singleton {
    id: root

    property alias gcal: _gcal
    property alias audio: _audio
    property alias bluetooth: _bluetooth
    property alias network: _network
    // The NixOS configuration the user chose and what they acknowledged about it
    // (distributions/nixos/NixosConfiguration.qml): remembered, not a preference — it names
    // this machine's folder
    property alias nixos: _nixos
    // Named presets of a widget's settings, { type: { name: { ... } } } as JSON — a shared
    // library a bar entry points into. "" until migrated from the old widgetProfiles.
    property alias widgetPresets: _adapter.widgetPresets
    // Profiles as a JSON array. "" means the config
    // predates profiles and Profiles seeds it; "[]" means the user deleted them all.
    property alias profiles: _adapter.profiles
    // Settings the user pinned as global, { key: value } as JSON: the same in every
    // profile
    property alias globals: _adapter.globals
    // Settings already copied from their old place in this file into the profiles, once
    // each
    property alias migratedKeys: _adapter.migratedKeys
    // The ids of the modules turned off (ModuleHost.setEnabled, `modules setEnabled`): a module
    // is on unless listed here. Global, not per profile: which code runs in the shell is not a
    // preference a profile switches.
    property alias disabledModules: _adapter.disabledModules
    // The ids of the built-in modules builtin.json lists as off that the user turned on
    // (ModuleInstallRules.enabledByLists): the counterpart of disabledModules
    property alias enabledModules: _adapter.enabledModules
    // The user's acknowledgements of modules, { <id>: { source, address, author, privileged } }
    // as JSON (ModuleInstallRules.parseAcknowledgements reads it: ModuleHost.acknowledgements),
    // "" while never written — the first start of the module host that confirms modules writes
    // it (the baseline). Written with setAcknowledgedModules
    readonly property string acknowledgedModulesText: _adapter.acknowledgedModules
    // Read from the file as it was loaded (ModuleInstallRules.readAcknowledgements tells "never
    // written" from "missing in a file that should hold it"): whether it held the key, and
    // the version that wrote it ("" for none)
    property bool acknowledgedModulesInFile: false
    property string writtenByAtLoad: ""
    // The config was written by a newer shell (MigrationRules.newerConfig, newerNotice): the
    // startup banner's text and its dismissal for this run
    property var newerNotice: MigrationRules.newerNotice(null, Version.number)
    property bool newerNoticeDismissed: false
    // The sleep notice's state (SleepLockNotice, SleepNoticeRules: JSON, "" while quiet):
    // remembered, so a restart neither repeats nor loses it
    property alias sleepLockNotice: _adapter.sleepLockNotice
    // The daily automatic module update run's state ({ lastAttemptAt, failures, lastOutcome }
    // as JSON, ModuleUpdateRules.autoRunRecord; "" never ran): remembered, so a restart does
    // not run it again
    property alias moduleUpdates: _adapter.moduleUpdates
    // The monitors the shell turned off and has not seen on again (Idle, IdleRules.turnedOff):
    // remembered, so a shell restarted while they are off turns them on again — and only them
    property alias screensOff: _adapter.screensOff
    // The file itself, for the backup taken before a migration
    readonly property string path: _file.path

    // True once the file has been read (or found missing, so the defaults stand) —
    // before that every property still holds its default
    property bool ready: false
    // The file is there but could not be read or is not a JSON object
    // (ProfileRules.configReadFailed): the properties hold their defaults, which are then
    // not what the user chose — settings where that matters fail safe on it
    property bool loadFailed: false
    // Set by the test runner: the suites load the real config, and nothing they change
    // may reach the user's file
    property bool readOnly: false
    property bool _refusedSave: false

    signal saved

    // Writes the acknowledgements (an object as ModuleHost.acknowledgements reads it; undefined writes
    // "never written", as a suite restoring the text does)
    function setAcknowledgedModules(list) {
        _adapter.acknowledgedModules = list === undefined ? "" : JSON.stringify(list);
    }

    // Puts back a text acknowledgedModulesText gave (a suite's restore)
    function setAcknowledgedModulesText(text) {
        _adapter.acknowledgedModules = typeof text === "string" ? text : "";
    }

    // The file holds a long-lived Google refresh token, and was created world-readable
    // (umask 022). Locking the directory keeps out every file in it, whatever its own mode
    // — backups, files written later — and the files get 600 as well. Once a run, after
    // the file has been read; never from the test runner.
    function _protectFiles() {
        if (!ready || readOnly || _protect.running)
            return;
        // The path is a file:// URL (StandardPaths gives URLs); chmod needs a plain path
        const file = _file.path.toString().replace(/^file:\/\//, "");
        _protect.command = ["sh", "-c", "chmod 700 \"$1\" && chmod 600 \"$1\"/config.json*", "sh",
                            file.substring(0, file.lastIndexOf("/"))];
        _protect.running = true;
    }

    // The file can finish loading while this singleton is still being built, before a
    // change handler would see it, so check on completion as well
    onReadyChanged: _protectFiles()
    Component.onCompleted: Qt.callLater(_protectFiles)

    Process {
        id: _protect
        // A failure is worth knowing: the token would stay readable to other users
        stderr: SplitParser { onRead: line => console.warn("[Config] could not restrict the config's permissions:", line) }
    }

    JsonConfigFile {
        id: _file
        path: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/h2s_shell/config.json"
        onAdapterUpdated: _saveTimer.restart()
        onLoaded: {
            root.loadFailed = ProfileRules.configReadFailed("", text());
            try {
                const data = JSON.parse(text());
                root.acknowledgedModulesInFile = data !== null && typeof data === "object" && Object.prototype.hasOwnProperty.call(data, "acknowledgedModules");
                root.writtenByAtLoad = typeof data?.writtenBy === "string" ? data.writtenBy : "";
                root.newerNotice = MigrationRules.newerNotice(
                    MigrationRules.newerConfig(data?.writtenBy, data?.migratedKeys, Version.number, Migrations.all()), Version.number);
            } catch (error) {
                root.acknowledgedModulesInFile = false;
                root.writtenByAtLoad = "";
                root.newerNotice = MigrationRules.newerNotice(null, Version.number);
            }
            if (root.newerNotice.shown)
                console.warn("[Config] " + root.newerNotice.log);
            if (root.loadFailed)
                console.warn("[Config] " + path + " is not a JSON object: its settings are not used");
            root.ready = true;
        }
        onLoadFailed: error => {
            root.loadFailed = ProfileRules.configReadFailed(error === FileViewError.FileNotFound ? "missing" : "error", "");
            if (root.loadFailed)
                console.warn("[Config] could not read " + path + ": " + FileViewError.toString(error));
            root.ready = true;
        }

        adapter: JsonAdapter {
            id: _adapter
            property string widgetPresets: ""
            property string profiles: ""
            property string globals: "{}"
            property list<string> migratedKeys: []
            property list<string> disabledModules: []
            property list<string> enabledModules: []
            // ModuleInstallRules.parseAcknowledgements' text: "" until first written
            property string acknowledgedModules: ""
            property string sleepLockNotice: ""
            property string moduleUpdates: ""
            property list<string> screensOff: []
            // The shell version that last wrote this file — for reference, and for
            // migrations that need to know what wrote it
            property string writtenBy: ""
            // Remembered per app by the volume sliders, not a preference
            property JsonObject audio: JsonObject {
                id: _audio
                property string appVolumes: "{}"
            }

            // Whether Bluetooth was left on, remembered by BluetoothPower, not a preference:
            // "" until it is first seen switched, then "on" or "off"
            property JsonObject bluetooth: JsonObject {
                id: _bluetooth
                property string powered: ""
            }

            // Which VPNs the shell brought up with a network, and which were taken down by
            // hand (VpnManager), so a restart keeps them — remembered, not a preference
            property JsonObject network: JsonObject {
                id: _network
                property string vpnMemory: "{}"
                // The blocking rules last loaded and the boot they were loaded in
                // (VpnLockdown: root's to read back, so remembered), and the VPN servers'
                // addresses last found
                property string lockdown: "{}"
            }

            // The NixOS configuration chosen with "Change…" (an absolute folder, "" for the
            // usual places) and the flake's host chosen with it ("" for /etc/hostname's), and
            // the real paths of configurations outside root's folders whose one-time warning
            // the user took
            property JsonObject nixos: JsonObject {
                id: _nixos
                property string folder: ""
                property string host: ""
                property list<string> homeWarningAcknowledged: []
            }

            // The Google account, its tokens and the calendars picked — data, not settings
            property JsonObject gcal: JsonObject {
                id: _gcal
                property string viewMode: "day"
                property string clientId: ""
                property string clientSecret: ""
                property string accessToken: ""
                property string refreshToken: ""
                property real tokenExpiry: 0
                property list<string> enabledCalendarIds: []
            }
        }
    }

    Timer {
        id: _saveTimer
        interval: 1000
        onTriggered: {
            // Never from the test runners, never over a file that could not be read
            // (ProfileRules.configSaveAllowed)
            if (!ProfileRules.configSaveAllowed(root.readOnly, root.loadFailed)) {
                if (!root.readOnly && !root._refusedSave)
                    console.warn("[Config] " + _file.path + " could not be read: changes are not saved over it");
                root._refusedSave = !root.readOnly;
                return;
            }
            _adapter.writtenBy = Version.number;
            _file.save();
            root.saved();
            _log.log("Saved");
        }
    }

    Logger {
        id: _log
        prefix: "[Config]"
        // The debug setting comes from Profiles, which is built on this Config: it is read
        // only once the file has loaded, so building Config does not need Profiles
        enabled: root.ready && (Profiles.value("general.debug") ?? false)
    }
}
