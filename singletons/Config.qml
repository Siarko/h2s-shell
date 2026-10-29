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

    property alias lockscreen: _lockscreen
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
            // Remembered per app by the volume sliders, not a preference
            property JsonObject audio: JsonObject {
                id: _audio
                property string appVolumes: "{}"
            }

            // Commands nothing runs yet (TODO 9.7); not in the schema until that is decided
            property JsonObject lockscreen: JsonObject {
                id: _lockscreen
                property bool screensaverExecCmd: false
                property string screensaverExecSleep: ''
                property string screensaverExecWakeup: ''
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
            _file.writeAdapter();
            root.saved();
            console.log("[CONFIG] Saved");
        }
    }
}
