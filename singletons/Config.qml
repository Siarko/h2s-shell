pragma Singleton

import Quickshell
import Quickshell.Io
import QtCore
import QtQuick
import qs.components

// The config file (ConfigFile, its keys declared in ConfigAdapter). Settings are not here: they live in the profiles (see Profiles and
// SettingsSchema). What is left is data that is not a
// preference — the Google account and its tokens, remembered per-app volumes — plus the
// widget preset library and the profiles themselves.
//
// Before the file is read the settings migrations run on it (ConfigFile.load: the registered
// migrations pending, a backup, the result written), so no reader sees an unmigrated value.
// A config written before profiles has its settings in sections this file no longer
// declares; a migration moves them into the profiles once they are seeded (Migrations,
// phase "afterSeed"). Saving keeps every
// key the file holds that is not declared (JsonConfigFile), so what a newer
// shell wrote survives this one; such a config also gets a warning (newerNotice), never a
// refusal.
Singleton {
    id: root

    readonly property alias gcal: _adapter.gcal
    readonly property alias audio: _adapter.audio
    readonly property alias bluetooth: _adapter.bluetooth
    readonly property alias network: _adapter.network
    // The NixOS configuration the user chose and what they acknowledged about it
    // (distributions/nixos/NixosConfiguration.qml): remembered, not a preference — it names
    // this machine's folder
    readonly property alias nixos: _adapter.nixos
    // Named presets of a widget's settings, { type: { name: { ... } } } as JSON — a shared
    // library a bar entry points into. "" until migrated from the old widgetProfiles.
    property alias widgetPresets: _adapter.widgetPresets
    // Profiles as a JSON array. "" means the config
    // predates profiles and Profiles seeds it; "[]" means the user deleted them all.
    property alias profiles: _adapter.profiles
    // Settings the user pinned as global, { key: value } as JSON: the same in every
    // profile
    property alias globals: _adapter.globals
    // The settings migrations applied (MigrationRules' records), and the per-key markers
    // older versions wrote
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
    readonly property alias acknowledgedModulesInFile: _file.acknowledgedModulesInFile
    readonly property alias writtenByAtLoad: _file.writtenByAtLoad
    // The config was written by a newer shell (ConfigFile): the startup banner's text, and
    // its dismissal for this run
    readonly property alias newerNotice: _file.newerNotice
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
    readonly property string path: _file.configPath
    // The settings migrations' last runs, { load, afterSeed } (ConfigFile.migrationReports):
    // what was applied, reset, skipped or held, the failure, the backup's path
    readonly property alias migrationReports: _file.migrationReports

    // True once the file has been read (or found missing, so the defaults stand) —
    // before that every property still holds its default
    property bool ready: false
    // The file is there but could not be read or is not a JSON object
    // (ProfileRules.configReadFailed): the properties hold their defaults, which are then
    // not what the user chose — settings where that matters fail safe on it
    readonly property alias loadFailed: _file.loadFailed
    // Set by the test runner: the suites load the real config, and nothing they change
    // may reach the user's file
    property bool readOnly: false
    // The migrations could not be run or written (ConfigFile.migrationReadOnly): the file
    // stays as it is for the session — changes take effect, they are not saved. Only the save
    // reads it; everything else runs as normal (readOnly means the test runner)
    readonly property bool saveBlocked: _file.migrationReadOnly
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
        const file = _file.configPath.toString().replace(/^file:\/\//, "");
        _protect.command = ["sh", "-c", "chmod 700 \"$1\" && chmod 600 \"$1\"/config.json*", "sh",
                            file.substring(0, file.lastIndexOf("/"))];
        _protect.running = true;
    }

    // The file can finish loading while this singleton is still being built, before a
    // change handler would see it, so check on completion as well
    // The after-seed migrations (ConfigFile.runAfterSeed), from Profiles once the profiles
    // exist; nothing until the file has been read
    function runAfterSeedMigrations() {
        if (ready)
            _file.runAfterSeed();
    }

    onReadyChanged: _protectFiles()
    // The migrations run before the file is read, one event-loop turn after this singleton is
    // built: the test runner sets readOnly right after building it, before anything may be
    // written
    Component.onCompleted: Qt.callLater(() => {
        _file.load();
        _protectFiles();
    })

    Process {
        id: _protect
        // A failure is worth knowing: the token would stay readable to other users
        stderr: SplitParser { onRead: line => console.warn("[Config] could not restrict the config's permissions:", line) }
    }

    ConfigFile {
        id: _file
        configPath: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/h2s_shell/config.json"
        readOnly: root.readOnly
        onAdapterUpdated: _saveTimer.restart()
        onRead: {
            if (newerNotice.shown)
                console.warn("[Config] " + newerNotice.log);
            if (loadFailed)
                console.warn("[Config] " + (readError !== "" ? "could not read " + path + ": " + readError : path + " is not a JSON object: its settings are not used"));
            root.ready = true;
        }
        adapter: ConfigAdapter {
            id: _adapter
        }
    }

    Timer {
        id: _saveTimer
        interval: 1000
        onTriggered: {
            // Not while the migrations hold the file (they said so in the log)
            if (root.saveBlocked)
                return;
            // Never from the test runners, never over a file that could not be read
            // (ProfileRules.configSaveAllowed)
            if (!ProfileRules.configSaveAllowed(root.readOnly, root.loadFailed)) {
                if (!root.readOnly && !root._refusedSave)
                    console.warn("[Config] " + _file.path + " could not be read: changes are not saved over it");
                root._refusedSave = !root.readOnly;
                return;
            }
            _file.saveStamped();
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
