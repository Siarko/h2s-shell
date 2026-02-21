pragma Singleton

import Quickshell
import Quickshell.Io
import QtCore
import QtQuick

Singleton {
    id: root

    property alias datetimeFormat: _calendar.datetimeFormat
    property alias gcal: _gcal

    FileView {
        id: _file
        path: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/h2s_shell/config.json"
        onAdapterUpdated: _saveTimer.restart()

        adapter: JsonAdapter {
            property JsonObject calendar: JsonObject {
                id: _calendar
                property string datetimeFormat: "hh:mm:ss"
            }

            property JsonObject gcal: JsonObject {
                id: _gcal
                property string clientId: ""
                property string clientSecret: ""
                property string accessToken: ""
                property string refreshToken: ""
                property real   tokenExpiry: 0
                property string enabledCalendarIds: "[]"
            }
        }
    }

    Timer {
        id: _saveTimer
        interval: 1000
        onTriggered: _file.writeAdapter()
    }
}
