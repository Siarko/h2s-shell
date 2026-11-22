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
    // Where monitors cannot be turned off, why (the backend's word) and what the screen-off
    // does instead, in place of the schema's hint; "" where they can
    readonly property string _powerOffHint: ScreenPower.canPowerOff ? ""
        : [(ScreenPower.unavailable?.reason || "Not supported here") + ": the black screensaver instead",
           ScreenPower.unavailable?.hint ?? ""].filter(part => part !== "").join(". ")

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

        Heading {
            text: "Lockscreen & Screensaver"
            Layout.bottomMargin: 8
        }

        // ── Screensaver ───────────────────────────────────────────────────

        SectionTitle { text: "Screensaver"; divider: false }

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
            key: "lockscreen.screenOffEnabled"
            editIndex: root.editIndex
            hint: root._powerOffHint
        }

        SchemaSettingEditor {
            key: "lockscreen.screenOffTimeout"
            editIndex: root.editIndex
            available: root._edited("lockscreen.screenOffEnabled") === true
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

        SectionTitle { text: "Lock screen" }

        SchemaSettingEditor {
            key: "lockscreen.lockscreenEnabled"
            editIndex: root.editIndex
        }

        SchemaSettingEditor {
            key: "lockscreen.lockAfter"
            editIndex: root.editIndex
            available: root._lockOn
        }

        SchemaSettingEditor {
            key: "lockscreen.lockedScreenOffTimeout"
            editIndex: root.editIndex
        }

        SchemaSettingEditor {
            key: "lockscreen.lockOnSleep"
            editIndex: root.editIndex
        }

        // The sleep notice was closed and no sleep has locked since (SleepLockNotice keeps the
        // state in the config; read from there, so the page starts no lock machinery)
        Hint {
            readonly property double waitingSince: SleepNoticeRules.waitingSince(
                SleepNoticeRules.restore(LockIoRules.sleepNoticeSaved(Config.sleepLockNotice)))
            objectName: "sleepNoticeWaiting"
            visible: waitingSince >= 0
            text: visible ? "Not locked while asleep (" + Qt.formatDateTime(new Date(waitingSince), "d MMM, hh:mm")
                            + "). Waiting for a sleep that locks." : ""
            color: Theme.warning
            Layout.topMargin: 4
            Layout.bottomMargin: 4
        }

        // Not tied to "Enable lock screen" (the idle lock): they apply to every lock — sleep,
        // a shortcut, another program locking the screen
        SchemaSettingEditor {
            key: "lockscreen.notificationsOnLock"
            editIndex: root.editIndex
        }

        SchemaSettingEditor {
            key: "lockscreen.lockNotificationDetail"
            editIndex: root.editIndex
            available: root._edited("lockscreen.notificationsOnLock") !== false
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
