import QtQuick
import QtQuick.Layouts
import qs.singletons

// Screensaver and lock screen settings, edited in the profile picked in the settings
// window.
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
    readonly property bool _commandsOn: _edited("lockscreen.screensaverCommands") === true

    anchors.fill: parent
    contentHeight: col.implicitHeight
    clip: true

    ColumnLayout {
        id: col
        anchors {
            fill: parent
            margins: Theme.settings.pageMargin
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
            color: Theme.textDisabled
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

        SchemaSettingEditor {
            key: "lockscreen.screensaverNotificationDetail"
            editIndex: root.editIndex
            available: root._screensaverOn && root._edited("lockscreen.notificationsOnScreensaver") !== false
        }

        SchemaSettingEditor {
            key: "lockscreen.screensaverCommands"
            editIndex: root.editIndex
            available: root._screensaverOn
        }

        SchemaSettingEditor {
            key: "lockscreen.screensaverStartCommand"
            editIndex: root.editIndex
            available: root._screensaverOn && root._commandsOn
        }

        SchemaSettingEditor {
            key: "lockscreen.screensaverEndCommand"
            editIndex: root.editIndex
            available: root._screensaverOn && root._commandsOn
        }
        // ── Lock screen ───────────────────────────────────────────────────

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 14
            color: Theme.textDisabled
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

        SchemaSettingEditor {
            key: "lockscreen.lockNotificationDetail"
            editIndex: root.editIndex
            available: root._lockOn && root._edited("lockscreen.notificationsOnLock") !== false
        }

        Item {
            Layout.fillHeight: true
        }
    }
}