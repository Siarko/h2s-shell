import QtQuick
import QtQuick.Layouts
import qs.singletons

Flickable {
    anchors.fill: parent
    contentHeight: col.implicitHeight
    clip: true

    ColumnLayout {
        id: col
        anchors {
            fill: parent
            margins: 14
        }
        spacing: 0

        Text {
            text: "Lockscreen & Screensaver"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.bottomMargin: 8
        }

        // ── Screensaver ───────────────────────────────────────────────────

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 4
            color: Theme.textDim
            opacity: 0.3
        }

        Text {
            text: "Screensaver"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.topMargin: 10
            Layout.bottomMargin: 4
        }

        SettingBool {
            label: "Enable screensaver"
            value: Config.lockscreen.screensaverEnabled
            onValueChanged: Config.lockscreen.screensaverEnabled = value
        }

        SettingIntInput {
            disabled: !Config.lockscreen.screensaverEnabled
            label: "Activate after"
            value: Config.lockscreen.screensaverTimeout
            from: 5
            suffix: "s"
            onValueEdited: newValue => Config.lockscreen.screensaverTimeout = newValue
        }

        SettingSlider {
            disabled: !Config.lockscreen.screensaverEnabled
            label: "Fade in"
            value: Config.lockscreen.fadeInDuration
            from: 100
            to: 2000
            suffix: "ms"
            onValueEdited: newValue => Config.lockscreen.fadeInDuration = newValue
        }

        SettingSlider {
            disabled: !Config.lockscreen.screensaverEnabled
            label: "Fade out"
            value: Config.lockscreen.fadeOutDuration
            from: 100
            to: 2000
            suffix: "ms"
            onValueEdited: newValue => Config.lockscreen.fadeOutDuration = newValue
        }

        SettingBool {
            disabled: !Config.lockscreen.screensaverEnabled
            label: "Show notifications on screensaver"
            value: Config.lockscreen.notificationsOnScreensaver
            onValueChanged: Config.lockscreen.notificationsOnScreensaver = value
        }

        SettingBool {
            disabled: !Config.lockscreen.screensaverEnabled
            label: "Execute command on screensaver enable/disable"
            value: Config.lockscreen.screensaverExecCmd
            onValueChanged: Config.lockscreen.screensaverExecCmd = value
        }

        SettingInputRow {
            disabled: !Config.lockscreen.screensaverEnabled || !Config.lockscreen.screensaverExecCmd
            label: "Screensaver enable command"
            inputWidthPercent: 50
            value: Config.lockscreen.screensaverExecSleep
            onValueChanged: Config.lockscreen.screensaverExecSleep = value

            Layout.leftMargin: 5
        }

        SettingInputRow {
            disabled: !Config.lockscreen.screensaverEnabled || !Config.lockscreen.screensaverExecCmd
            label: "Screensaver disable command"
            inputWidthPercent: 50
            value: Config.lockscreen.screensaverExecWakeup
            onValueChanged: Config.lockscreen.screensaverExecWakeup = value

            Layout.leftMargin: 5
        }
        // ── Lock screen ───────────────────────────────────────────────────

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 14
            color: Theme.textDim
            opacity: 0.3
        }

        Text {
            text: "Lock screen"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.topMargin: 10
            Layout.bottomMargin: 4
        }

        SettingBool {
            label: "Enable lock screen"
            value: Config.lockscreen.lockscreenEnabled
            onValueChanged: Config.lockscreen.lockscreenEnabled = value
        }

        SettingIntInput {
            disabled: !Config.lockscreen.lockscreenEnabled
            label: Config.lockscreen.screensaverEnabled ? "Lock after screensaver" : "Lock after"
            value: Config.lockscreen.lockscreenTimeout
            from: 5
            suffix: "s"
            onValueEdited: newValue => Config.lockscreen.lockscreenTimeout = newValue
        }

        SettingBool {
            disabled: !Config.lockscreen.lockscreenEnabled
            label: "Show notifications on lock screen"
            value: Config.lockscreen.notificationsOnLock
            onValueChanged: Config.lockscreen.notificationsOnLock = value
        }

        Item {
            Layout.fillHeight: true
        }
    }
}