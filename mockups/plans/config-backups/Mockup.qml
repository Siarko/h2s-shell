import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import qs.singletons
import qs.components
import qs.mockups.kit

// Planning mockup of the config backups in Settings (a list with Apply, Make a backup now,
// Delete) and of the settings-update failure notice (the critical notification and its
// Dashboard entry). One stand-in Settings window (1000 x 620) with a note under it per scene.
// Throwaway: the window's frame, the sidebar, the backup rows and the Dashboard entry are drawn
// here as proposals; the real pieces used are the theme, SettingsPage, SettingsSection,
// SmallButton, SettingsModal and NotificationCard. Stand-in data: this shell is 2.2.0, now is
// the kit's 15 Jan 2026, 10:30. Scenes and wording: MOCKUP.md.
// The last scene, config-backups-live, is the same window working on its own stand-in data:
// backups made, applied and deleted, the failed update's notice raised from the note under the
// window, with the theme's animations (off in the other scenes and while shooting).
MockupWindow {
    id: root

    contentWidth: 1000
    contentHeight: 690

    readonly property int windowWidth: 1000
    readonly property int windowHeight: 620
    readonly property int sidebarWidth: Theme.scaled(160)
    readonly property string thisVersion: "2.2.0"

    function sceneIs(...wanted) {
        return wanted.indexOf(root.current) >= 0;
    }

    readonly property bool live: current === "config-backups-live"
    readonly property bool onDashboard: live ? livePage === "dashboard" : sceneIs("failure-dashboard", "failure-restore-confirm")

    // The live scene animates as the shell would; every other scene, and every shot, is drawn
    // without motion (the entry makes animations instant)
    onCurrentChanged: {
        Theme.instantAnimations = !(live && !shooting);
        if (live)
            Qt.callLater(() => listKeys.forceActiveFocus());
    }

    // ---- Stand-in data ---------------------------------------------------------------------

    // reason: migration | module | restore | manual | "" (an older backup, none recorded);
    // updates: how many settings updates Apply would run on it; failing: the scope a preview
    // finds failing under this version
    readonly property var madeNow: ({ key: "m0", date: "15 Jan 2026, 10:30", reason: "manual", version: "2.2.0",
        file: "config.json.bak-2026-01-15T10-30-00-manual", updates: 0 })
    readonly property var backups: [
        { key: "r1", date: "14 Jan 2026, 18:02", reason: "restore", version: "2.2.0",
          file: "config.json.bak-2026-01-14T18-02-11-restore", updates: 0 },
        { key: "u1", date: "12 Jan 2026, 09:14", reason: "module", module: "Tailscale 1.2.0 → 1.3.0", version: "2.2.0",
          file: "config.json.bak-2026-01-12T09-14-40-module", updates: 0 },
        { key: "g1", date: "10 Jan 2026, 08:41", reason: "migration", version: "2.1.0",
          file: "config.json.bak-2026-01-10T08-41-02-migration", updates: 1 },
        { key: "n1", date: "8 Jan 2026, 22:15", reason: "migration", version: "2.3.0", newer: true,
          file: "config.json.bak-2026-01-08T22-15-57-migration", updates: 0 },
        { key: "k1", date: "5 Jan 2026, 21:30", reason: "manual", version: "2.1.0",
          file: "config.json.bak-2026-01-05T21-30-00-manual", updates: 1 },
        { key: "o1", date: "20 Dec 2025, 14:05", reason: "", version: "2.0.1",
          file: "config.json.bak-2025-12-20T14-05-33", updates: 3, failing: "music widget presets" },
        { key: "o2", date: "1 Dec 2025, 11:47", reason: "", version: "",
          file: "config.json.bak-2025-12-01T11-47-09", updates: 4 }
    ]
    readonly property var shownBackups: live ? liveBackups : sceneIs("backup-made") ? [madeNow].concat(backups) : backups

    // ---- The live scene's state ------------------------------------------------------------

    property var liveBackups: backups.slice()
    property string liveSelected: ""
    // "apply" | "delete" | "restore" | ""
    property string liveModal: ""
    // "backups" | "dashboard"
    property string livePage: "backups"
    // The date of the backup Make a backup now made last; "" hides the line
    property string liveMade: ""
    property bool liveToast: false
    property bool liveFailure: false
    property bool liveDetails: false
    // The stand-in clock: each backup made takes the next minute after 10:30
    property int liveMinute: 30
    property int liveSerial: 0
    // What the stand-in shell did last (a restart), said in the note under the window
    property string liveEvent: ""

    function liveReset() {
        liveBackups = backups.slice();
        liveSelected = "";
        liveModal = "";
        livePage = "backups";
        liveMade = "";
        liveToast = false;
        liveFailure = false;
        liveDetails = false;
        liveMinute = 30;
        liveEvent = "";
        listKeys.forceActiveFocus();
    }

    // A new backup at the top, at the stand-in clock's next minute; automatic ones pruned to
    // the newest 10
    function liveAdd(reason) {
        const minute = liveMinute++;
        const hh = 10 + Math.floor(minute / 60), mm = minute % 60;
        const pad = n => (n < 10 ? "0" : "") + n;
        const backup = { key: "live" + (++liveSerial), date: "15 Jan 2026, " + hh + ":" + pad(mm), reason: reason, version: thisVersion,
                         file: "config.json.bak-2026-01-15T" + pad(hh) + "-" + pad(mm) + "-00-" + reason, updates: 0, fresh: true };
        let automatic = 0;
        liveBackups = [backup].concat(liveBackups).filter(item => item.reason === "manual" || ++automatic <= 10);
        return backup;
    }

    function liveMakeBackup() {
        const backup = liveAdd("manual");
        liveMade = backup.date;
        liveSelected = backup.key;
    }

    function liveMove(step) {
        const keys = liveBackups.map(backup => backup.key);
        if (keys.length === 0)
            return;
        const at = keys.indexOf(liveSelected);
        liveSelected = keys[at < 0 ? (step > 0 ? 0 : keys.length - 1) : Math.max(0, Math.min(keys.length - 1, at + step))];
    }

    function liveAsk(which) {
        if ((which === "apply" || which === "delete") && !selectedBackup)
            return;
        liveModal = which;
    }

    function liveAnswer(confirmed) {
        const which = liveModal;
        liveModal = "";
        if (!confirmed)
            return;
        if (which === "delete") {
            liveBackups = liveBackups.filter(backup => backup.key !== liveSelected);
            liveSelected = "";
            liveMade = "";
        } else if (which === "apply") {
            const applied = selectedBackup;
            liveAdd("restore");
            liveSelected = "";
            liveMade = "";
            liveEvent = "The shell restarted with the backup of " + applied.date + ".";
        } else if (which === "restore") {
            liveAdd("restore");
            liveFailure = false;
            liveToast = false;
            liveDetails = false;
            livePage = "backups";
            liveEvent = "The shell restarted with the settings from before the update.";
        }
    }

    function liveFail() {
        liveFailure = true;
        liveToast = true;
        liveDetails = false;
        liveEvent = "The shell started after an update to 2.2.0; one settings update failed.";
    }

    function liveKeepDefaults() {
        liveFailure = false;
        liveToast = false;
        liveDetails = false;
    }

    readonly property string selectedKey: {
        if (live)
            return liveSelected;
        if (sceneIs("selected", "apply-confirm"))
            return "g1";
        if (sceneIs("apply-confirm-failing"))
            return "o1";
        if (sceneIs("newer-version", "newer-confirm"))
            return "n1";
        if (sceneIs("delete-confirm"))
            return "k1";
        if (sceneIs("backup-made"))
            return "m0";
        return "";
    }
    readonly property var selectedBackup: shownBackups.find(backup => backup.key === selectedKey) ?? null

    function reasonText(backup) {
        switch (backup.reason) {
        case "migration": return "Before a settings update";
        case "module": return "Before updating " + backup.module;
        case "restore": return "Before a restore";
        case "manual": return "Made by you";
        default: return "Older backup, reason not recorded";
        }
    }

    // The short reason the delete question names, as the owner's draft has it ("ręczna")
    function reasonShort(backup) {
        switch (backup.reason) {
        case "migration": return "before a settings update";
        case "module": return "before a module update";
        case "restore": return "before a restore";
        case "manual": return "manual";
        default: return "reason not recorded";
        }
    }

    function versionText(backup) {
        return backup.version !== "" ? backup.version : "version unknown";
    }

    function updatesText(count) {
        if (count === 0)
            return "No settings updates are needed: it is loaded as it is.";
        return count + (count === 1 ? " settings update brings" : " settings updates bring") + " it up to " + root.thisVersion + ".";
    }

    readonly property string newerWarning: "Written by h2s-shell 2.3.0, newer than this version: what this version does not know is kept, unused; nothing is converted back."

    // The modal each scene shows, as SettingsModal takes it
    readonly property string modalWhich: live ? liveModal
        : sceneIs("apply-confirm", "apply-confirm-failing", "newer-confirm") ? "apply"
        : sceneIs("delete-confirm") ? "delete"
        : sceneIs("failure-restore-confirm") ? "restore" : ""
    readonly property var modalSpec: {
        const backup = selectedBackup;
        if (modalWhich === "apply" && backup) {
            const body = [];
            if (backup.newer)
                body.push({ text: newerWarning, strong: true });
            body.push(reasonText(backup) + " · written by h2s-shell " + versionText(backup) + ".");
            body.push("1. Your current settings are saved first, as a new backup (Before a restore): nothing is lost.");
            body.push("2. This backup is loaded. " + updatesText(backup.updates));
            if (backup.failing)
                body.push({ text: "One of them fails under this version: " + backup.failing + ". That part is loaded as it was and stays unused (it behaves as defaults) until the next update of the shell, which tries again.", strong: true });
            body.push("3. The shell restarts to finish.");
            return { kind: "warning", title: "Apply the backup of " + backup.date + "?", body: body,
                     buttons: [{ label: "Apply and restart", kind: "warning" }], cancelLabel: "Cancel" };
        }
        if (modalWhich === "delete" && backup)
            return { kind: "danger", title: "Delete the backup of " + backup.date + " (" + reasonShort(backup) + ", " + versionText(backup) + ")?",
                     body: ["Only this backup is removed. This cannot be undone."],
                     buttons: [{ label: "Delete", kind: "delete" }], cancelLabel: "Cancel" };
        if (modalWhich === "restore")
            return { kind: "warning", title: "Restore your settings from before the update?",
                     body: ["Your current settings are saved first, as a new backup (Before a restore): nothing set since is lost.",
                            "Your settings from before the update come back. The part that failed (music widget presets) stays unused until the next update of the shell, which tries again.",
                            "The shell restarts to finish."],
                     buttons: [{ label: "Restore and restart", kind: "warning" }], cancelLabel: "Cancel" };
        return null;
    }

    readonly property string failureSummary: "Some settings were reset to defaults"
    readonly property string failureBody: "Updating your settings for 2.2.0 failed for: music widget presets (Popup mode is now a widget action). That part now uses its defaults; the rest of your settings were updated. Your previous settings are kept in the backup of 15 Jan 2026, 10:29."

    // Plain object: what NotificationCard reads
    readonly property var failureNotification: ({
        id: 9101, appName: "h2s-shell", summary: failureSummary, body: failureBody, appIcon: "", hints: ({}),
        urgency: NotificationUrgency.Critical,
        // The live scene's answers, after the card's own click handler is done: they remove the card
        actions: [{ identifier: "keep", text: "Keep defaults", invoke: () => Qt.callLater(root.liveKeepDefaults) },
                  { identifier: "restore", text: "Restore previous settings", invoke: () => Qt.callLater(() => { root.livePage = "dashboard"; root.liveModal = "restore"; }) },
                  { identifier: "details", text: "Details", invoke: () => Qt.callLater(() => { root.livePage = "dashboard"; root.liveDetails = true; }) }]
    })
    readonly property string failureFile: "config.json.bak-2026-01-15T10-29-00-migration"

    readonly property var notes: ({
        "list": "System → Backups (proposed place). Newest first: the date, why it was made, the version that wrote it. Manual backups carry \"Kept\": only the automatic ones are pruned to the newest 10. The older backups made before reasons were recorded say so. Make a backup now is on the section's title line.",
        "backup-made": "After Make a backup now: the new manual backup at the top, selected, and a line under the title that says it was made. No toast, no notification.",
        "selected": "A row clicked is selected and opens: its file name, what Apply would do (how many settings updates would run, from the preview), and its two buttons — Apply and Delete. Every backup has both, manual or automatic.",
        "apply-confirm": "Apply asks first (Settings modal, warning): the backup's reason and version, then the three steps — the current settings backed up, this one loaded and brought up to date, the shell restarts.",
        "apply-confirm-failing": "The same question when the preview finds an update that would fail under this version: the part it names is loaded as it was and stays unused until the next shell update tries again. Apply stays available.",
        "newer-version": "A backup written by a newer shell (2.3.0): the version in the warning colour with ⚠ in the row, and the full warning when selected. Apply is still there — never refused.",
        "newer-confirm": "Its question leads with the warning (bold), then the usual steps; no settings updates run (nothing is converted back).",
        "delete-confirm": "Delete asks in the Settings modal (danger), naming the date, reason and version, as the owner's draft: only that one file goes.",
        "failure-notification": "A settings update failed at start: one critical notification (red border, no timeout, kept in the history) with Keep defaults / Restore previous settings / Details. A successful update is never announced.",
        "failure-dashboard": "The same notice as an entry on the Settings Dashboard (HS-176, still a sketch: only this entry is proposed), kept until Keep defaults. The same three choices.",
        "failure-restore-confirm": "Restore previous settings asks first (from the notification or the Dashboard): the current settings backed up, the pre-update ones back, the failed part unused until the next shell update; restart.",
        "config-backups-live": "Live, on stand-in data. Keys: ↑ ↓ select, Enter apply, Delete delete, Esc deselect; Tab in the questions."
    })

    // ---- Stand-in pieces ------------------------------------------------------------------

    component Label: Text {
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textPrimary
        textFormat: Text.PlainText
    }

    // A small marker chip: "Kept"
    component Chip: Rectangle {
        property string text
        property color tone: Theme.accent
        implicitWidth: _chipText.implicitWidth + 14
        implicitHeight: _chipText.implicitHeight + 4
        radius: height / 2
        color: Qt.alpha(tone, 0.18)
        border.width: Theme.border.width
        border.color: tone
        Text {
            id: _chipText
            anchors.centerIn: parent
            text: parent.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: parent.tone
        }
    }

    // One backup in the list; opened while selected
    component BackupRow: Rectangle {
        id: _row
        required property var backup
        readonly property bool selected: backup.key === root.selectedKey
        implicitHeight: _rowColumn.implicitHeight + 16
        radius: Theme.settings.cardRadius
        color: selected ? Theme.accentTint : _rowArea.containsMouse && root.live ? Theme.surfaceHover : Theme.surface
        border.width: selected ? Theme.border.selectedWidth : 0
        border.color: Theme.accent
        clip: true
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
        Behavior on implicitHeight { NumberAnimation { duration: Theme.duration("expand"); easing: Theme.curve("expand") } }

        // A backup just made fades in (live scene)
        NumberAnimation on opacity {
            running: _row.backup.fresh === true
            from: 0; to: 1
            duration: Theme.duration("enter")
            easing: Theme.curve("enter")
        }

        // The live scene: a click selects the row, a second one closes it
        MouseArea {
            id: _rowArea
            anchors.fill: parent
            enabled: root.live
            hoverEnabled: true
            onClicked: {
                root.liveSelected = _row.selected ? "" : _row.backup.key;
                listKeys.forceActiveFocus();
            }
        }

        ColumnLayout {
            id: _rowColumn
            x: 12; y: 8
            width: parent.width - 24
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Label {
                    Layout.preferredWidth: Theme.scaled(150)
                    text: _row.backup.date
                    font.bold: true
                }
                Label {
                    Layout.fillWidth: true
                    text: root.reasonText(_row.backup)
                    color: _row.backup.reason === "" ? Theme.textMuted : Theme.textSecondary
                    elide: Text.ElideRight
                }
                Chip {
                    visible: _row.backup.reason === "manual"
                    text: "󰐃 Kept"
                }
                Label {
                    Layout.preferredWidth: Theme.scaled(110)
                    horizontalAlignment: Text.AlignRight
                    text: (_row.backup.newer ? "⚠ " : "") + root.versionText(_row.backup)
                    color: _row.backup.newer ? Theme.warning : (_row.backup.version === "" ? Theme.textMuted : Theme.textSecondary)
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
            Label {
                visible: _row.selected && _row.backup.newer === true
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "⚠ " + root.newerWarning
                color: Theme.warning
                font.pixelSize: Theme.fontSizeSmall
            }
            Label {
                visible: _row.selected
                Layout.fillWidth: true
                text: _row.backup.file + (_row.backup.reason === "manual" ? " · kept until you delete it" : "")
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
            RowLayout {
                visible: _row.selected
                Layout.fillWidth: true
                spacing: 8
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Apply: " + root.updatesText(_row.backup.updates)
                          + (_row.backup.failing ? " One fails under this version (" + _row.backup.failing + ")." : "")
                    color: _row.backup.failing ? Theme.warning : Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }
                SmallButton { label: "Apply…"; tooltip: "Load this backup and restart the shell"; onClicked: root.liveAsk("apply") }
                SmallButton { label: "Delete…"; kind: "delete"; onClicked: root.liveAsk("delete") }
            }
        }
    }

    component SidebarItem: Rectangle {
        id: _item
        property string label
        property bool picked: false
        property bool line: false
        // The live scene's page it opens; "" for the stand-ins
        property string page: ""
        width: root.sidebarWidth - 16
        height: 30
        radius: Theme.settings.sidebarItemRadius
        color: picked ? Theme.accentTint : "transparent"
        Rectangle { visible: parent.line; width: parent.width; height: 1; color: Theme.textDisabled; opacity: 0.3; y: -4 }
        Label {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: parent.picked ? Theme.textPrimary : Theme.textSecondary
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.live && _item.page !== ""
            onClicked: root.livePage = _item.page
        }
    }

    component Tab: Rectangle {
        property string label
        property bool picked: false
        width: _tabText.implicitWidth + 24
        height: 28
        radius: 6
        color: picked ? Theme.accentTint : "transparent"
        Label {
            id: _tabText
            anchors.centerIn: parent
            text: parent.label
            color: parent.picked ? Theme.textPrimary : Theme.textMuted
        }
    }

    // ---- The Settings window --------------------------------------------------------------

    Rectangle {
        id: settingsWindow
        visible: !root.sceneIs("failure-notification")
        width: root.windowWidth
        height: root.windowHeight
        color: Theme.popupBackground
        clip: true

        Item {
            id: tabBar
            width: parent.width
            height: 44
            Label {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "Settings"
                font.pixelSize: Theme.fontSizeMedium
                font.bold: true
            }
            Row {
                x: root.sidebarWidth + 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Tab { label: "Behaviour" }
                Tab { label: "Appearance" }
                Tab { label: "System"; picked: !root.onDashboard }
            }
            Rectangle { width: parent.width; height: 1; anchors.bottom: parent.bottom; color: Theme.textDisabled; opacity: 0.3 }
        }

        Column {
            x: 8; y: tabBar.height + 10
            spacing: 6
            SidebarItem { label: "󰕮  Dashboard" + (root.live && root.liveFailure ? "  ⚠" : ""); picked: root.onDashboard; page: "dashboard" }
            SidebarItem { label: "Authentication"; line: true }
            SidebarItem { label: "Network" }
            SidebarItem { label: "Modules" }
            SidebarItem { label: "Backups"; picked: !root.onDashboard; page: "backups" }
        }

        Rectangle {
            x: root.sidebarWidth; y: tabBar.height
            width: 1; height: parent.height - tabBar.height
            color: Theme.textDisabled; opacity: 0.3
        }

        // The page area
        Item {
            id: pageArea
            x: root.sidebarWidth + 1; y: tabBar.height
            width: parent.width - x
            height: parent.height - y
            property string anchorBase: "settings.backups"

            // The live scene's keyboard on the list: ↑ ↓ select, Enter asks to apply, Delete to
            // delete, Escape closes the row
            Item {
                id: listKeys
                Keys.onPressed: event => {
                    if (!root.live || root.onDashboard)
                        return;
                    if (event.key === Qt.Key_Down)
                        root.liveMove(1);
                    else if (event.key === Qt.Key_Up)
                        root.liveMove(-1);
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        root.liveAsk("apply");
                    else if (event.key === Qt.Key_Delete)
                        root.liveAsk("delete");
                    else if (event.key === Qt.Key_Escape)
                        root.liveSelected = "";
                    else
                        return;
                    event.accepted = true;
                }
            }

            SettingsPage {
                visible: !root.onDashboard
                anchors.fill: parent
                title: "Backups"
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Copies of your settings file, all profiles included. Apply loads one, brings it up to this version and restarts the shell. Modules' stores and data have their own backups, on the Modules page."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textSecondary
                }

                SettingsSection {
                    Layout.fillWidth: true
                    title: "Settings backups"
                    spacing: 6
                    buttons: SmallButton {
                        label: "Make a backup now"
                        checked: root.sceneIs("backup-made")
                        onClicked: if (root.live) root.liveMakeBackup()
                    }

                    Text {
                        visible: root.live ? root.liveMade !== "" : root.sceneIs("backup-made")
                        Layout.fillWidth: true
                        text: "✓ Backup made: " + (root.live ? root.liveMade : "15 Jan 2026, 10:30")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.success
                    }
                    Repeater {
                        model: ScriptModel { values: root.shownBackups.map(backup => backup.key) }
                        BackupRow {
                            required property string modelData
                            backup: root.shownBackups.find(item => item.key === modelData)
                            Layout.fillWidth: true
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        wrapMode: Text.WordWrap
                        text: "Automatic backups (before a settings update, a module update or a restore): the newest 10 are kept. Manual backups stay until you delete them."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textMuted
                    }
                }
            }

            // The Dashboard (HS-176 is a sketch): only the failure entry is the proposal
            SettingsPage {
                visible: root.onDashboard
                anchors.fill: parent
                title: "Dashboard"
                spacing: 10

                Rectangle {
                    visible: !root.live || root.liveFailure
                    Layout.fillWidth: true
                    implicitHeight: _entry.implicitHeight + 24
                    radius: Theme.settings.cardRadius
                    color: Qt.alpha(Theme.error, 0.10)
                    border.width: Theme.border.selectedWidth
                    border.color: Theme.error
                    ColumnLayout {
                        id: _entry
                        x: 14; y: 12
                        width: parent.width - 28
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Label { text: "⚠"; color: Theme.error; font.pixelSize: Theme.fontSizeBodyLarge }
                            Label { text: root.failureSummary; font.bold: true; font.pixelSize: Theme.fontSizeBodyLarge; Layout.fillWidth: true }
                            Label { text: "today, 10:29"; color: Theme.textMuted; font.pixelSize: Theme.fontSizeSmall }
                        }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: root.failureBody
                            color: Theme.textSecondary
                        }
                        Label {
                            visible: root.live && root.liveDetails
                            Layout.fillWidth: true
                            text: root.failureFile
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Item { Layout.fillWidth: true }
                            SmallButton { label: "Keep defaults"; tooltip: "Close this notice; the old values stay in the backup"; onClicked: root.liveKeepDefaults() }
                            SmallButton {
                                label: "Restore previous settings…"
                                kind: "warning"
                                checked: root.modalWhich === "restore"
                                onClicked: if (root.live) root.liveAsk("restore")
                            }
                            SmallButton { label: "Details"; checked: root.live && root.liveDetails; onClicked: root.liveDetails = !root.liveDetails }
                        }
                    }
                }
                // Stand-ins for the Dashboard's other content
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: Theme.settings.cardRadius
                    color: Theme.surface
                    Label { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "✓  Modules: 3 running"; color: Theme.textMuted }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: Theme.settings.cardRadius
                    color: Theme.surface
                    Label { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "✓  Arch integration: connected"; color: Theme.textMuted }
                }
            }
        }

        SettingsModal {
            anchors.fill: parent
            open: root.modalSpec !== null
            kind: root.modalSpec?.kind ?? "info"
            title: root.modalSpec?.title ?? ""
            body: root.modalSpec?.body ?? []
            buttons: root.modalSpec?.buttons ?? []
            cancelLabel: root.modalSpec?.cancelLabel ?? ""
            onAnswered: index => root.liveAnswer(!buttonList[index].cancel)
            onRequested: event => root.liveAnswer(false)
        }
    }

    // ---- The live scene's notification, over the window's top right corner ------------------

    Loader {
        x: root.windowWidth - 412
        y: 52
        width: 400
        active: root.live && root.liveToast
        sourceComponent: Item {
            id: _toastBox
            width: 400
            height: _liveToast.height
            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity { NumberAnimation { duration: Theme.duration("enter"); easing: Theme.curve("enter") } }
            NotificationCard {
                id: _liveToast
                width: parent.width
                notification: root.failureNotification
                compactDismiss: true
                timestamp: "now"
                onDismissRequested: Qt.callLater(() => root.liveToast = false)
            }
        }
    }

    // ---- The desktop with the critical notification ----------------------------------------

    Rectangle {
        visible: root.sceneIs("failure-notification")
        width: root.windowWidth
        height: root.windowHeight
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.surface }
            GradientStop { position: 1; color: Theme.barBackground }
        }
        Rectangle {
            width: parent.width
            height: Theme.bar.barHeight
            color: Theme.barBackground
            Label {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "󰂚  1    10:30"
            }
        }
        // In an item of its own: the card keeps its own x (its swipe)
        Item {
            x: parent.width - width - 12
            y: Theme.bar.reservedSpace + 8
            width: 400
            height: _toast.height
            NotificationCard {
                id: _toast
                width: parent.width
                notification: root.failureNotification
                compactDismiss: true
                timestamp: "now"
            }
        }
        Label {
            x: 40; y: 300
            width: 460
            wrapMode: Text.WordWrap
            text: "Stand-in desktop, the shell just started after an update to 2.2.0."
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // The note under the window
    Rectangle {
        y: root.windowHeight
        width: root.contentWidth
        height: root.contentHeight - root.windowHeight
        color: Theme.surfaceSunken
        Row {
            id: _liveControls
            visible: root.live
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 8
            spacing: 8
            SmallButton { label: "Failed update"; kind: "warning"; tooltip: "Start as after an update whose settings update failed"; onClicked: root.liveFail() }
            SmallButton { label: "Reset"; tooltip: "Back to the stand-in data"; onClicked: root.liveReset() }
        }
        Text {
            x: 14; y: 8
            width: parent.width - 28 - (root.live ? _liveControls.width + 14 : 0)
            wrapMode: Text.WordWrap
            text: "<b>" + root.current + "</b> — " + (root.notes[root.current] ?? "")
                  + (root.live && root.liveEvent !== "" ? "<br>" + root.liveEvent : "")
            textFormat: Text.StyledText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textSecondary
        }
    }
}
