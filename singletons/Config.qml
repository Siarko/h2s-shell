pragma Singleton

import Quickshell
import Quickshell.Io
import QtCore
import QtQuick

// The config file. Settings are not here: they live in the profiles (see Profiles and
// SettingsSchema, docs/plans/global-profiles.md). What is left is data that is not a
// preference — the Google account and its tokens, remembered per-app volumes — plus the
// widget preset library and the profiles themselves.
//
// A config written before profiles has its settings in sections this file no longer
// declares; Profiles reads those from the raw file once to migrate them, and the first
// save then drops them.
Singleton {
    id: root

    property alias gcal: _gcal
    property alias audio: _audio
    // Named presets of a widget's settings, { type: { name: { ... } } } as JSON — a shared
    // library a bar entry points into. "" until migrated from the old widgetProfiles.
    property alias widgetPresets: _adapter.widgetPresets
    // Profiles (docs/plans/global-profiles.md) as a JSON array. "" means the config
    // predates profiles and Profiles seeds it; "[]" means the user deleted them all.
    property alias profiles: _adapter.profiles
    // Settings the user pinned as global, { key: value } as JSON: the same in every
    // profile (docs/plans/global-profiles.md)
    property alias globals: _adapter.globals
    // Settings already copied from their old place in this file into the profiles, once
    // each (docs/plans/global-profiles.md)
    property alias migratedKeys: _adapter.migratedKeys
    // The file itself, for the backup taken before a migration
    readonly property string path: _file.path

    // True once the file has been read (or found missing, so the defaults stand) —
    // before that every property still holds its default
    property bool ready: false
    // Set by the test runner: the suites load the real config, and nothing they change
    // may reach the user's file
    property bool readOnly: false

    signal saved

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

    FileView {
        id: _file
        path: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/h2s_shell/config.json"
        onAdapterUpdated: _saveTimer.restart()
        onLoaded: root.ready = true
        onLoadFailed: root.ready = true

        adapter: JsonAdapter {
            id: _adapter
            property string widgetPresets: ""
            property string profiles: ""
            property string globals: "{}"
            property list<string> migratedKeys: []
            // The shell version that last wrote this file — for reference, and for
            // migrations that need to know what wrote it
            property string writtenBy: ""
            // Remembered per app by the volume sliders, not a preference
            property JsonObject audio: JsonObject {
                id: _audio
                property string appVolumes: "{}"
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
            if (root.readOnly)
                return;
            _adapter.writtenBy = Version.number;
            _file.writeAdapter();
            root.saved();
            console.log("[CONFIG] Saved");
        }
    }
}
