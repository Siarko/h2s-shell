pragma Singleton

import Quickshell
import Quickshell.Io
import QtCore
import QtQuick

Singleton {
    id: root

    property alias datetimeFormat: _calendar.datetimeFormat
    property alias gcal: _gcal
    property alias general: _general
    property alias media: _media

    signal saved

    FileView {
        id: _file
        path: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/h2s_shell/config.json"
        onAdapterUpdated: _saveTimer.restart()

        adapter: JsonAdapter {
            property JsonObject general: JsonObject {
                id: _general
                property bool debug: false
                property bool fetch_debug: false
            }
            property JsonObject calendar: JsonObject {
                id: _calendar
                property string datetimeFormat: "hh:mm:ss"
            }

            property JsonObject media: JsonObject {
                id: _media
                property string visualizerStyle: "waveform"   // "waveform"|"bars"|"dots"|"none"
                property string visualizerLayout: "horizontal" // "horizontal"|"vertical"
            }

            property JsonObject gcal: JsonObject {
                id: _gcal
                property string clientId: ""
                property string clientSecret: ""
                property string accessToken: ""
                property string refreshToken: ""
                property real tokenExpiry: 0
                property list<string> enabledCalendarIds: []
                property bool debug: false
            }
        }
    }

    Timer {
        id: _saveTimer
        interval: 1000
        onTriggered: {
            _file.writeAdapter();
            root.saved();
            console.log("[CONFIG] Saved");
        }
    }
}
