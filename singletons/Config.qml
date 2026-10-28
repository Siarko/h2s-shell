pragma Singleton

import Quickshell
import Quickshell.Io
import QtCore
import QtQuick

Singleton {
    id: root

    property alias datetimeFormat: _calendar.datetimeFormat
    property alias bar: _bar
    property alias lockscreen: _lockscreen
    property alias gcal: _gcal
    property alias general: _general
    property alias media: _media
    property alias audio: _audio
    property alias notifications: _notifications
    property alias widgetProfiles: _adapter.widgetProfiles

    signal saved

    FileView {
        id: _file
        path: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/h2s_shell/config.json"
        onAdapterUpdated: _saveTimer.restart()

        adapter: JsonAdapter {
            id: _adapter
            property string widgetProfiles: "{}"
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

            property JsonObject bar: JsonObject {
                id: _bar
                property JsonObject content: JsonObject {
                    id: _barContent
                    property list<string> left: ["power", "settings", "workspaces"]
                    property list<string> center: ["clock"]
                    property list<string> right: ["music", "sound", "bluetooth", "tray", "network", "notifications"]
                    property string leftProfiles:   "[]"
                    property string centerProfiles: "[]"
                    property string rightProfiles:  "[]"
                }
                property JsonObject layout: JsonObject {
                    id: _barLayout
                    property int reservedSpace: 40
                    property int barHeight: 36
                    property int topOffset: 2
                    property int leftMargin: 0
                    property int rightMargin: 0
                    property int leftPadding: 5
                    property int rightPadding: 5
                    property int radiusTopLeft: 0
                    property int radiusTopRight: 0
                    property int radiusBottomLeft: 20
                    property int radiusBottomRight: 20
                }
            }

            property JsonObject audio: JsonObject {
                id: _audio
                property string appVolumes: "{}"
            }

            property JsonObject notifications: JsonObject {
                id: _notifications
                property list<string> codePatterns: ["\\d{4,8}"]
            }

            property JsonObject lockscreen: JsonObject {
                id: _lockscreen
                property bool screensaverEnabled: false
                property bool screensaverExecCmd: false
                property string screensaverExecSleep: ''
                property string screensaverExecWakeup: ''
                property int  screensaverTimeout: 300
                property bool lockscreenEnabled: false
                property int  lockscreenTimeout: 300
                property int  fadeInDuration: 800
                property int  fadeOutDuration: 400
                property bool notificationsOnScreensaver: true
                property bool notificationsOnLock: true
            }

            property JsonObject gcal: JsonObject {
                id: _gcal
                property bool enabled: true
                property string viewMode: "day"
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
