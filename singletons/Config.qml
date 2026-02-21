pragma Singleton

import Quickshell
import Quickshell.Io
import QtCore
import QtQuick

Singleton {
    id: root

    property alias datetimeFormat: _calendar.datetimeFormat

    FileView {
        id: _file
        path: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/h2s_shell/config.json"
        onAdapterUpdated: _saveTimer.restart()

        adapter: JsonAdapter {
            property JsonObject calendar: JsonObject {
                id: _calendar
                property string datetimeFormat: "hh:mm:ss"
            }
        }
    }

    Timer {
        id: _saveTimer
        interval: 1000
        onTriggered: _file.writeAdapter()
    }
}
