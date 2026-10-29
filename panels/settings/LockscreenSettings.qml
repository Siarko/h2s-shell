import QtQuick
import QtQuick.Layouts
import qs.singletons

// Screensaver and lock screen settings, edited in the profile picked in the settings
// window. The command settings are not in the schema yet — nothing runs them (TODO 9.7) —
// so they still apply to every profile.
Flickable {
    id: root

    // The profile being edited, picked in the settings window
    property int editIndex: -1

    // A setting's value in the edited profile, for greying out what depends on it
    function _edited(key) {
        if (key in Profiles.effectiveGlobals)
            return Profiles.effectiveGlobals[key]
        return Profiles.profiles[editIndex]?.set?.[key] ?? Profiles.inheritedValue(editIndex, key)
    }
    readonly property bool _screensaverOn: _edited("lockscreen.screensaverEnabled") === true
    readonly property bool _lockOn: _edited("lockscreen.lockscreenEnabled") === true

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

        SchemaSettingEditor {
            key: "lockscreen.screensaverEnabled"
            editIndex: root.editIndex
        }

        SchemaSettingEditor {
            key: "lockscreen.screensaverTimeout"
            editIndex: root.editIndex
            available: root._screensaverOn
        }

        SchemaSettingEditor {
            key: "lockscreen.fadeInDuration"
            editIndex: root.editIndex
            available: root._screensaverOn
        }

        SchemaSettingEditor {
            key: "lockscreen.fadeOutDuration"
            editIndex: root.editIndex
            available: root._screensaverOn
        }

        SchemaSettingEditor {
            key: "lockscreen.notificationsOnScreensaver"
            editIndex: root.editIndex
            available: root._screensaverOn
        }

        Text {
            Layout.topMargin: 6
            text: "The commands below apply to every profile."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textDim
        }

        SettingBool {
            disabled: !root._screensaverOn
            label: "Execute command on screensaver enable/disable"
            value: Config.lockscreen.screensaverExecCmd
            onValueChanged: Config.lockscreen.screensaverExecCmd = value
        }

        SettingInputRow {
            disabled: !root._screensaverOn || !Config.lockscreen.screensaverExecCmd
            label: "Screensaver enable command"
            inputWidthPercent: 50
            value: Config.lockscreen.screensaverExecSleep
            onValueChanged: Config.lockscreen.screensaverExecSleep = value

            Layout.leftMargin: 5
        }

        SettingInputRow {
            disabled: !root._screensaverOn || !Config.lockscreen.screensaverExecCmd
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

        SchemaSettingEditor {
            key: "lockscreen.lockscreenEnabled"
            editIndex: root.editIndex
        }

        SchemaSettingEditor {
            key: "lockscreen.lockscreenTimeout"
            editIndex: root.editIndex
            available: root._lockOn
            label: root._screensaverOn ? "Lock after screensaver" : "Lock after"
        }

        SchemaSettingEditor {
            key: "lockscreen.notificationsOnLock"
            editIndex: root.editIndex
            available: root._lockOn
        }

        Item {
            Layout.fillHeight: true
        }
    }
}