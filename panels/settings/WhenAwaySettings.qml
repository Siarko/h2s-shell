import QtQuick
import Quickshell
import QtQuick.Layouts
import qs.components
import qs.singletons

// "When away": what happens while nobody uses the computer, edited in the profile picked in
// the settings window. Its sections in the order things happen — the screensaver (and the
// screens turned off), the lock screen, sleep, hibernation —, then what keeps the screen on
// and the commands;
// each stage's switch on its section's title line. At the top, under the page's heading
// and without a title of its own: "Set per monitor" and the timeline of it all.
Flickable {
    id: root

    // The profile being edited, picked in the settings window
    property int editIndex: -1
    // A section to show at the top once the page stands ("lock": the lock screen's — the
    // sleep notice's click); "" none
    property string section: ""

    // A setting's value in the edited profile, for the timeline and for dimming what
    // depends on it
    function _edited(key) {
        if (key in Profiles.effectiveGlobals)
            return Profiles.effectiveGlobals[key];
        return Profiles.profiles[editIndex]?.set?.[key] ?? Profiles.inheritedValue(editIndex, key);
    }
    readonly property bool _saverOn: _edited("lockscreen.screensaverEnabled") === true
    readonly property bool _offOn: _edited("lockscreen.screenOffEnabled") === true
    readonly property bool _lockOn: _edited("lockscreen.lockscreenEnabled") === true
    readonly property bool _perMonitor: _edited("lockscreen.perMonitor") === true
    readonly property bool _commandsOn: _edited("lockscreen.screensaverCommands") === true
    readonly property bool _sleepOn: _edited("lockscreen.sleepEnabled") === true
    readonly property bool _lockOnSleep: _edited("lockscreen.lockOnSleep") === true
    // What logind allows and does about sleep (Idle.sleepSupport), and its sleep blocks
    // (Idle.sleepBlockers)
    property var sleepSupport: Idle.sleepSupport
    property var sleepBlockers: Idle.sleepBlockers
    // The shell sleeps the computer only on "yes"
    readonly property string _canSuspend: sleepSupport?.canSuspend ?? "unknown"
    readonly property string _sleepUnavailable: AwayViewRules.sleepUnavailable(_canSuspend)
    readonly property bool _hibernateOn: _edited("lockscreen.hibernateEnabled") === true
    // What explains hibernation here and the system's delay (Idle.sleepSupport's hibernation)
    readonly property var _hibernation: sleepSupport?.hibernation ?? ({})
    // logind's answer for the call the shell would make: SuspendThenHibernate with sleep on,
    // Hibernate with it off
    readonly property string _hibernateUnavailable: HibernateRules.unavailable(Object.assign({
        answer: _config.sleepAfter > 0 ? sleepSupport?.canSuspendThenHibernate : sleepSupport?.canHibernate
    }, _hibernation))
    // { on, from, at, after } (IdleRules.config)
    readonly property var _hibernate: _config.hibernate
    // … as it will happen: with sleep on the system's delay, until an Apply changes it — what
    // the timeline and the line under the times show (the pills keep the profile's time)
    readonly property var _hibernateInEffect: HibernateRules.inEffect(_hibernate, _hibernation.delay)
    // With sleep on, the profile's time after sleeping is not the system's delay: said, with
    // Apply (or, on NixOS, the module's option)
    readonly property bool _delayDiffers: _config.sleepAfter > 0 && HibernateRules.delayDiffers(_hibernation.delay, _hibernate.after)
    // What the last Apply wrote (Idle.hibernateDelayWritten), and the file that wins over it
    // when the delay read back is still another: named, and no Apply while it does
    property int delayWritten: Idle.hibernateDelayWritten
    readonly property string _delayOverride: HibernateRules.delayOverride(_hibernation.delay, delayWritten)
    readonly property var _monitorMap: _edited("lockscreen.monitorIdle")
    // The map comes from a profile above, or the default: its cards' choices dimmed
    readonly property bool _mapInherited: !("lockscreen.monitorIdle" in Profiles.effectiveGlobals)
        && Profiles.profiles[editIndex]?.set?.["lockscreen.monitorIdle"] === undefined
    readonly property bool _canPowerOff: Idle.powerControl

    // The edited profile's times as idle reads them (IdleRules.config), for the connected
    // monitors
    readonly property var _config: IdleRules.config({
        screensaverEnabled: _saverOn,
        screensaverTimeout: _edited("lockscreen.screensaverTimeout"),
        screenOffEnabled: _offOn,
        screenOffTimeout: _edited("lockscreen.screenOffTimeout"),
        lockscreenEnabled: _lockOn,
        lockAfter: _edited("lockscreen.lockAfter"),
        lockedScreenOffTimeout: _edited("lockscreen.lockedScreenOffTimeout"),
        perMonitor: _perMonitor,
        monitorIdle: _monitorMap,
        screensaverCommands: _commandsOn,
        sleepEnabled: _sleepOn,
        sleepTimeout: _edited("lockscreen.sleepTimeout"),
        lockOnSleep: _lockOnSleep,
        hibernateEnabled: _hibernateOn,
        hibernateTimeout: _edited("lockscreen.hibernateTimeout")
    }, Idle.monitors, _canPowerOff, _canSuspend, sleepSupport?.canHibernate, sleepSupport?.canSuspendThenHibernate)
    // The timeline's lanes: one per connected monitor while per monitor, else one for all
    // The connected monitors' names, twins told apart by their connectors
    readonly property var _monitorNames: AwayViewRules.monitorNames(Idle.monitors)
    readonly property var _lanes: _perMonitor && Idle.monitors.length > 0
        ? Idle.monitors.map((monitor, index) => ({
            key: monitor.id,
            name: _monitorNames[index],
            times: _config.times[monitor.id] ?? { saverAfter: _config.saverAfter, screenOffAfter: _config.screenOffAfter }
        }))
        : [{ key: "all", name: "", times: { saverAfter: _config.saverAfter, screenOffAfter: _config.screenOffAfter } }]
    readonly property var _laneTimes: _lanes.map(lane => lane.times)
    readonly property bool _anySaver: AwayViewRules.anySaver(_laneTimes, _canPowerOff)
    readonly property int _allDarkAt: AwayViewRules.allDarkAt(_laneTimes)

    // The default's four times, as a monitor's own start from them (IdleRules.monitorTimes)
    readonly property var _defaultTimes: {
        const time = (value, fallback) => {
            const number = Math.round(Number(value));
            return Number.isFinite(number) ? Math.min(IdleRules.monitorTimeRange.maximum, Math.max(IdleRules.monitorTimeRange.minimum, number)) : fallback;
        };
        return {
            screensaverEnabled: _saverOn,
            screensaverTimeout: time(_edited("lockscreen.screensaverTimeout"), 300),
            screenOffEnabled: _offOn,
            screenOffTimeout: time(_edited("lockscreen.screenOffTimeout"), 600)
        };
    }

    // The cards: each connected monitor, then those with times kept and not connected
    readonly property var _cardKeys: Idle.monitors.map(monitor => monitor.id)
        .concat(MonitorRules.notConnected(_monitorMap, Idle.monitors))

    // One monitor's times written into the edited profile's map: `key` a connected monitor's
    // id or a kept entry's key, `times` its whole entry or "default"
    function setMonitorTimes(key, times) {
        const monitor = Idle.monitors.find(entry => entry.id === key) ?? key;
        const map = IdleRules.withMonitorTimes(_monitorMap, monitor, times, Idle.monitors);
        if (map === null)
            return false;
        return Profiles.writeSetting(editIndex, "lockscreen.monitorIdle", map) !== false;
    }

    // Where monitors cannot be turned off, why (the backend's word) and what the screen-off
    // does instead; "" where they can
    readonly property string _powerOffHint: _canPowerOff ? ""
        : [(ScreenPower.unavailable?.reason || "Not supported here") + ": the black screensaver instead",
           ScreenPower.unavailable?.hint ?? ""].filter(part => part !== "").join(". ")

    // The sections by name, for `section`
    readonly property var sections: ({ screensaver: _saverSection, lock: _lockSection, sleep: _sleepSection,
                                       hibernate: _hibernateSection, awake: _awakeSection, commands: _commandsSection })

    function showSection(name) {
        const target = sections[name];
        if (!target)
            return false;
        const y = target.mapToItem(_column, 0, 0).y;
        contentY = Math.max(0, Math.min(y, contentHeight - height));
        return true;
    }

    onSectionChanged: Qt.callLater(_showRequested)
    Component.onCompleted: {
        // What logind allows may have changed since the start (a polkit rule, a new kernel)
        Idle.refreshSleepSupport();
        Qt.callLater(_showRequested);
    }
    function _showRequested() {
        if (section !== "")
            showSection(section);
    }

    anchors.fill: parent
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: _column
        x: Theme.settings.pageMargin
        y: Theme.settings.pageMargin
        width: root.width - 2 * Theme.settings.pageMargin
        spacing: 0

        Heading {
            text: "When away"
            Layout.bottomMargin: 8
        }

        // ── The top: under the heading, without a title of its own ──────────

        SchemaSettingEditor {
            key: "lockscreen.perMonitor"
            editIndex: root.editIndex
            hint: root._perMonitor ? "Each monitor its own screensaver and screen-off times. Lock, sleep and hibernation are one for all."
                                   : "One set of times for every monitor."
        }

        AwayTimeline {
            objectName: "awayTimeline"
            Layout.fillWidth: true
            Layout.topMargin: 2
            lanes: root._lanes
            perMonitor: root._perMonitor
            lockAfter: root._config.lockAfter
            commandsAt: root._commandsOn ? root._allDarkAt : -1
            sleepAfter: root._config.sleepAfter
            hibernate: root._hibernateInEffect
            sleepBlockers: root.sleepBlockers
            lockedScreenOffAfter: root._config.lockedScreenOffAfter
            canPowerOff: root._canPowerOff
            holders: Idle.holders
        }

        Hint {
            text: "Counted from your last input, on any monitor."
            Layout.topMargin: 2
        }

        // ── Screensaver: its switch on the title line, the screens turned off, the look ──

        SettingsSection {
            id: _saverSection
            objectName: "screensaverSection"
            title: root._perMonitor ? "Screensaver (all monitors)" : "Screensaver"
            Layout.fillWidth: true
            spacing: 2
            buttons: SchemaSettingEditor {
                objectName: "screensaverSwitch"
                key: "lockscreen.screensaverEnabled"
                editIndex: root.editIndex
                inline: true
                labelShown: false
                Layout.fillWidth: false
            }

            Reveal {
                objectName: "screensaverTimes"
                open: root._saverOn
                SchemaSettingEditor {
                    key: "lockscreen.screensaverTimeout"
                    editIndex: root.editIndex
                    inline: true
                    label: "after"
                }
            }

            SchemaSettingEditor {
                key: "lockscreen.screenOffEnabled"
                editIndex: root.editIndex
                hint: root._powerOffHint
            }

            Reveal {
                objectName: "screenOffTimes"
                open: root._offOn
                SchemaSettingEditor {
                    key: "lockscreen.screenOffTimeout"
                    editIndex: root.editIndex
                    inline: true
                    label: "after"
                }
            }

            // Per monitor: the map's own line (where it comes from, the pin) and a card each
            Reveal {
                objectName: "monitorCards"
                open: root._perMonitor
                spacing: 8
                SchemaSettingEditor {
                    key: "lockscreen.monitorIdle"
                    editIndex: root.editIndex
                    inline: true
                    Layout.topMargin: 6
                }
                Repeater {
                    model: ScriptModel { values: root._cardKeys }

                    MonitorTimesCard {
                        required property string modelData
                        readonly property var monitor: Idle.monitors.find(entry => entry.id === modelData) ?? null
                        objectName: "monitorCard"
                        name: monitor ? root._monitorNames[Idle.monitors.findIndex(entry => entry.id === modelData)] : AwayViewRules.monitorName(modelData, "")
                        connector: monitor?.connector ?? ""
                        own: {
                            const entry = monitor ? MonitorRules.overrideFor(root._monitorMap, monitor, Idle.monitors)
                                                  : root._monitorMap?.[modelData];
                            return entry !== null && typeof entry === "object" ? entry : null;
                        }
                        defaults: root._defaultTimes
                        dimmed: root._mapInherited
                        canPowerOff: root._canPowerOff
                        onEdited: times => root.setMonitorTimes(modelData, times)
                    }
                }
            }

            // How the screensaver looks: dimmed, never hidden, while no monitor shows it
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 10
                Layout.bottomMargin: 4
                text: root._anySaver ? "How it looks" : "How it looks — used once a monitor shows the screensaver"
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                color: Theme.textMuted
            }

            ColumnLayout {
                objectName: "screensaverLook"
                Layout.fillWidth: true
                spacing: 2
                enabled: root._anySaver
                opacity: enabled ? 1 : 0.4
                Behavior on opacity { NumberAnimation { duration: Theme.duration("fade") } }

                SchemaSettingEditor {
                    key: "lockscreen.fadeInDuration"
                    editIndex: root.editIndex
                    inline: true
                }
                SchemaSettingEditor {
                    key: "lockscreen.fadeOutDuration"
                    editIndex: root.editIndex
                    inline: true
                }
                SchemaSettingEditor {
                    key: "lockscreen.notificationsOnScreensaver"
                    editIndex: root.editIndex
                    label: "Show notifications"
                }
                Reveal {
                    open: root._edited("lockscreen.notificationsOnScreensaver") !== false
                    SchemaSettingEditor {
                        key: "lockscreen.screensaverNotificationDetail"
                        editIndex: root.editIndex
                        inline: true
                        labelShown: false
                    }
                }
            }
        }

        // ── Lock screen: the idle lock's switch on the title line; the rest serves every lock ──

        SettingsSection {
            id: _lockSection
            objectName: "lockSection"
            title: "Lock screen"
            Layout.fillWidth: true
            spacing: 2
            buttons: SchemaSettingEditor {
                objectName: "lockSwitch"
                key: "lockscreen.lockscreenEnabled"
                editIndex: root.editIndex
                inline: true
                label: "Lock when idle"
                Layout.fillWidth: false
            }

            Hint {
                text: "Also for a lock by hand and before sleep."
                Layout.bottomMargin: 4
            }
            // Off: only the idle lock's time is dimmed
            ColumnLayout {
                objectName: "lockTimes"
                Layout.fillWidth: true
                spacing: 0
                enabled: root._lockOn
                opacity: enabled ? 1 : 0.4
                Behavior on opacity { NumberAnimation { duration: Theme.duration("fade") } }

                SchemaSettingEditor {
                    key: "lockscreen.lockAfter"
                    editIndex: root.editIndex
                    inline: true
                    label: "after"
                }
                Hint {
                    visible: root._perMonitor
                    text: "One lock for the whole session."
                    Layout.bottomMargin: 4
                }
            }

            SchemaSettingEditor {
                key: "lockscreen.lockOnSleep"
                editIndex: root.editIndex
                Layout.topMargin: 4
            }

            // The sleep notice was closed and no sleep has locked since (SleepLockNotice keeps
            // the state in the config; read from there, so the page starts no lock machinery)
            Reveal {
                id: _waiting
                readonly property double waitingSince: SleepNoticeRules.waitingSince(
                    SleepNoticeRules.restore(LockIoRules.sleepNoticeSaved(Config.sleepLockNotice)))
                open: waitingSince >= 0
                Hint {
                    objectName: "sleepNoticeWaiting"
                    text: _waiting.waitingSince >= 0
                          ? "Not locked while asleep (" + Qt.formatDateTime(new Date(_waiting.waitingSince), "d MMM, hh:mm")
                            + "). Waiting for a sleep that locks." : ""
                    color: Theme.warning
                    Layout.bottomMargin: 4
                }
            }

            SchemaSettingEditor {
                key: "lockscreen.lockedScreenOffTimeout"
                editIndex: root.editIndex
                label: "Turn screens off on the lock screen"
                hint: root._canPowerOff ? "Without input on the lock screen" : "Not supported here: the lock screen turns black"
            }

            SchemaSettingEditor {
                key: "lockscreen.notificationsOnLock"
                editIndex: root.editIndex
                label: "Show notifications on the lock screen"
            }
            Reveal {
                open: root._edited("lockscreen.notificationsOnLock") !== false
                SchemaSettingEditor {
                    key: "lockscreen.lockNotificationDetail"
                    editIndex: root.editIndex
                    inline: true
                    labelShown: false
                }
            }

            SettingsRow {
                Layout.topMargin: 4
                label: "Signing in"
                hint: "Password. Fingerprint and security key are set on the Authentication page."
                SmallButton {
                    objectName: "authenticationPage"
                    label: "Authentication"
                    fontSize: Theme.fontSizeSmall
                    onClicked: Shell.openSettings("authentication")
                }
            }
        }

        // ── Sleep: the whole computer, its switch on the title line ──────────

        SettingsSection {
            id: _sleepSection
            objectName: "sleepSection"
            title: "Sleep"
            Layout.fillWidth: true
            spacing: 2
            buttons: SchemaSettingEditor {
                objectName: "sleepSwitch"
                key: "lockscreen.sleepEnabled"
                editIndex: root.editIndex
                inline: true
                labelShown: false
                available: root._sleepUnavailable === ""
                Layout.fillWidth: false
            }

            Hint {
                objectName: "sleepCaption"
                text: root._sleepUnavailable !== "" ? root._sleepUnavailable + "."
                    : root._sleepOn ? "The computer sleeps when nobody has used it for this long."
                    : "The computer does not sleep by itself when idle."
                Layout.bottomMargin: 4
            }

            Reveal {
                objectName: "sleepTimes"
                open: root._sleepOn && root._sleepUnavailable === ""
                SchemaSettingEditor {
                    key: "lockscreen.sleepTimeout"
                    editIndex: root.editIndex
                    inline: true
                    label: "after"
                }
                Hint {
                    objectName: "sleepLockLine"
                    text: AwayViewRules.sleepLockLine({
                        lockOnSleep: root._lockOnSleep, lockAfter: root._config.lockAfter, sleepAfter: root._config.sleepAfter
                    }, seconds => Format.duration(seconds))
                    Layout.bottomMargin: 4
                }
            }

            // logind sleeps the computer by itself too (its IdleAction): said, not prevented
            Rectangle {
                id: _systemSleeps
                readonly property string text: AwayViewRules.systemSleeps(root.sleepSupport?.idleAction ?? null, seconds => Format.duration(seconds))
                objectName: "systemSleeps"
                visible: text !== ""
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: visible ? _systemSleepsText.implicitHeight + 14 : 0
                radius: Theme.settings.cardRadius
                color: Qt.alpha(Theme.warning, 0.10)
                border.width: Theme.border.width
                border.color: Theme.warning
                Text {
                    id: _systemSleepsText
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                    text: _systemSleeps.text
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textPrimary
                }
            }
        }

        // ── Hibernate: the whole computer, its switch on the title line ──────

        SettingsSection {
            id: _hibernateSection
            objectName: "hibernateSection"
            title: "Hibernate"
            Layout.fillWidth: true
            spacing: 2
            buttons: SchemaSettingEditor {
                objectName: "hibernateSwitch"
                key: "lockscreen.hibernateEnabled"
                editIndex: root.editIndex
                inline: true
                labelShown: false
                available: root._hibernateUnavailable === ""
                Layout.fillWidth: false
            }

            Hint {
                objectName: "hibernateCaption"
                text: AwayViewRules.hibernateCaption(root._hibernateUnavailable, root._hibernate.from)
                Layout.bottomMargin: 4
            }

            Reveal {
                objectName: "hibernateTimes"
                open: root._hibernateOn && root._hibernateUnavailable === ""
                SchemaSettingEditor {
                    objectName: "hibernateTimeout"
                    key: "lockscreen.hibernateTimeout"
                    editIndex: root.editIndex
                    inline: true
                    label: AwayViewRules.hibernatePillsLabel(root._hibernate.from)
                }
                Hint {
                    objectName: "hibernateLine"
                    text: AwayViewRules.hibernateLine(root._hibernateInEffect, seconds => Format.duration(seconds))
                    Layout.bottomMargin: 4
                }
                // With sleep on the delay is the system's, one per machine: a time that differs
                // is said, with Apply where the shell may write it (the password asked on the
                // click), or the NixOS option's name
                RowLayout {
                    objectName: "hibernateDelay"
                    visible: root._delayDiffers
                    Layout.fillWidth: true
                    spacing: 8
                    Hint {
                        objectName: "hibernateDelayLine"
                        text: HibernateRules.delayLine(root._hibernation.delay, root._hibernation.nixos ?? null, seconds => Format.duration(seconds),
                                                       root._delayOverride, root._hibernate.after)
                        Layout.fillWidth: true
                    }
                    SmallButton {
                        objectName: "hibernateApply"
                        visible: root._hibernation.nixos === false && root._delayOverride === ""
                        label: Idle.hibernateDelayApplying ? "Applying…" : "Apply"
                        kind: "save"
                        available: !Idle.hibernateDelayApplying
                        fontSize: Theme.fontSizeSmall
                        onClicked: Idle.applyHibernateDelay(root._hibernate.after)
                    }
                }
            }
        }

        // ── Keeping the screen on: who holds it now ──────────────────────────

        SettingsSection {
            id: _awakeSection
            objectName: "awakeSection"
            title: "Keeping the screen on"
            Layout.fillWidth: true
            spacing: 4

            Hint {
                visible: Idle.holders.length === 0
                text: "Nothing right now."
            }
            Repeater {
                model: ScriptModel { values: Idle.holders.map((holder, index) => String(index)) }

                SettingsRow {
                    required property string modelData
                    readonly property var holder: Idle.holders[Number(modelData)] ?? { who: "", why: "" }
                    objectName: "holderRow"
                    label: holder.who.charAt(0).toUpperCase() + holder.who.slice(1)
                    hint: holder.why
                }
            }
            // Another program answers apps' requests to keep the screen on
            Hint {
                visible: Idle.screenSaverService.state === "taken"
                text: Idle.screenSaverService.line
                color: Theme.warning
            }
            Hint {
                Layout.topMargin: 4
                text: "Apps that ask to keep the screen on delay the screensaver, the screens turned off, the lock, sleep and hibernation, on every monitor. Not on the lock screen."
            }
        }

        // ── Commands ───────────────────────────────────────────────────────

        SettingsSection {
            id: _commandsSection
            objectName: "commandsSection"
            title: "Commands"
            Layout.fillWidth: true
            spacing: 4

            // Dimmed, not hidden, while no monitor goes dark: their moment never comes
            ExpandingRow {
                objectName: "commandsRow"
                label: "Run commands"
                hint: !root._commandsOn ? "Off"
                    : root._allDarkAt >= 0 ? "On, at " + Format.duration(root._allDarkAt) + ", when every screen is dark"
                    : "On, when every screen is dark"
                enabled: root._allDarkAt >= 0
                opacity: enabled ? 1 : 0.4

                ColumnLayout {
                    spacing: 0
                    SchemaSettingEditor {
                        key: "lockscreen.screensaverCommands"
                        editIndex: root.editIndex
                    }
                    SchemaSettingEditor {
                        key: "lockscreen.screensaverStartCommand"
                        editIndex: root.editIndex
                        available: root._commandsOn
                    }
                    SchemaSettingEditor {
                        key: "lockscreen.screensaverEndCommand"
                        editIndex: root.editIndex
                        available: root._commandsOn
                    }
                }
            }
        }
    }
}
