import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// System → Backups: the config backups (ConfigBackupList, read each time the page shows),
// newest first — the date, why it was made (a manual one marked Kept: never pruned), the
// version that wrote it (a newer writer marked). Make a backup now writes a manual one, which
// comes in at the top, opened. A row clicked opens: the file's name, a newer writer's one
// line, what Apply would do (its preview, run in memory), Apply…, whose question in the
// Settings modal is a steps list keyed to the backup and what it holds, and Delete…, which
// asks naming the backup (not the one being applied or the failure notice's restore needs).
Item {
    id: root

    // ConfigBackupList (MigrationNotice.backups), or a stand-in
    property var backups: MigrationNotice.backups
    // SettingsModalHost, or a stand-in: ask(spec, onAnswer) → "" when it opened
    property var modalHost: null
    property string version: Version.number

    // The opened row's name ("" none), and its preview
    property string selected: ""
    property var preview: null
    // Why the last Apply or Delete did not start or finish ("" none)
    property string problem: ""
    // The backup Make a backup now made last ("" none), and why the last one was not made
    property string made: ""
    property string backupProblem: ""
    // A backup made, opened once the list holds it; and faded in as it comes
    property string _openWhenListed: ""
    property string _fadeIn: ""

    readonly property var _rows: backups?.rows ?? []
    readonly property var _selectedRow: _rows.find(row => row.name === selected) ?? null

    // A row that went (deleted, pruned) closes; a backup just made opens once it is listed
    on_RowsChanged: {
        if (_openWhenListed !== "" && _rows.some(row => row.name === _openWhenListed)) {
            const name = _openWhenListed;
            _openWhenListed = "";
            select(name);
        } else if (selected !== "" && !_rows.some(row => row.name === selected)) {
            select("");
        }
    }

    // The list's keys: ↑ ↓ open the row above or below, Enter asks to apply, Delete asks to
    // delete
    activeFocusOnTab: true
    Keys.onPressed: event => {
        if (root.handleKey(event.key))
            event.accepted = true;
    }

    // → whether the key was taken
    function handleKey(key) {
        if (key === Qt.Key_Up || key === Qt.Key_Down) {
            const names = _rows.map(row => row.name);
            if (names.length === 0)
                return true;
            const at = names.indexOf(selected);
            const step = key === Qt.Key_Down ? 1 : -1;
            select(names[at < 0 ? (step > 0 ? 0 : names.length - 1) : Math.max(0, Math.min(names.length - 1, at + step))]);
            return true;
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            askApply();
            return true;
        }
        if (key === Qt.Key_Delete) {
            askDelete();
            return true;
        }
        return false;
    }

    // Make a backup now: a manual backup of the settings as saved
    function makeBackup() {
        backupProblem = "";
        if (!backups)
            return false;
        const refusal = backups.makeBackup(result => {
            if (!result.ok) {
                root.backupProblem = result.problem;
                return;
            }
            root.made = result.name;
            root._fadeIn = result.name;
            root._openWhenListed = result.name;
        });
        backupProblem = refusal;
        return refusal === "";
    }

    // Why the row's backup cannot be deleted now ("" it can)
    function deleteRefusal(name) {
        return backups ? backups.deleteRefusal(name) : "Could not start";
    }

    // Delete's question for the opened row; its answer deletes the backup asked about
    function askDelete() {
        const row = _selectedRow;
        if (!row || !modalHost)
            return false;
        // Said where it is seen: Delete from the keyboard has no tooltip
        const refusal = deleteRefusal(row.name);
        if (refusal !== "") {
            problem = refusal;
            return false;
        }
        return modalHost.ask(ConfigBackupRules.deleteQuestion(row), answer => {
            if (answer.cancelled || answer.button !== "delete")
                return;
            root.problem = root.backups.deleteBackup(answer.subject.name, result => {
                if (!result.ok)
                    root.problem = result.problem;
            });
        }) === "";
    }

    function select(name) {
        problem = "";
        selected = name;
        preview = name !== "" && backups ? backups.preview(name) : null;
    }

    // Apply's question for the opened row; its answer acts on the backup asked about
    function askApply() {
        const row = _selectedRow;
        if (!row || !row.readable || !modalHost)
            return false;
        const spec = ConfigBackupRules.applyQuestion(row, preview, version);
        return modalHost.ask(spec, answer => {
            if (answer.cancelled || answer.button !== "apply")
                return;
            root.problem = root.backups.apply(answer.subject.name, answer.subject.held);
        }) === "";
    }

    PageShown {
        onBecameShown: root.backups?.refresh()
    }

    KeyedModel {
        id: _keyed
        values: root._rows
        keyProp: "key"
    }

    SettingsPage {
        anchors.fill: parent
        title: "Backups"
        spacing: 8

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Copies of your settings file, all profiles included. Modules' stores and data: on the Modules page."
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textSecondary
        }

        SettingsSection {
            Layout.fillWidth: true
            title: "Settings backups"
            spacing: 6
            buttons: SmallButton {
                objectName: "backupNow"
                label: "Make a backup now"
                onClicked: root.makeBackup()
            }

            Text {
                objectName: "backupMade"
                visible: root.made !== "" && root._rows.some(row => row.name === root.made)
                Layout.fillWidth: true
                text: ConfigBackupRules.madeLine(root.made)
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.success
            }
            // Why the last Apply or Delete did not start or finish: under the title, seen
            // whichever row is open
            Text {
                objectName: "backupProblem"
                visible: root.problem !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.problem
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
            }
            Text {
                objectName: "backupNowProblem"
                visible: root.backupProblem !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.backupProblem
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
            }

            Text {
                objectName: "backupsEmpty"
                visible: root.backups?.known === true && root._rows.length === 0
                Layout.fillWidth: true
                text: "No backups yet."
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textMuted
            }

            Repeater {
                model: _keyed.model
                delegate: BackupRow {
                    required property string modelData
                    row: _keyed.byKey[modelData] ?? null
                    Layout.fillWidth: true
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                wrapMode: Text.WordWrap
                text: "Automatic backups: the newest " + MigrationRules.backupsKept + " are kept."
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }
        }
    }

    // One backup; opened while selected
    component BackupRow: Rectangle {
        id: _row
        property var row: null
        readonly property bool opened: row !== null && row.name === root.selected
        objectName: "backupRow"
        implicitHeight: _rowColumn.implicitHeight + 16
        radius: Theme.settings.cardRadius
        color: opened ? Theme.accentTint : _rowArea.lit ? Theme.surfaceHover : Theme.surface
        border.width: opened ? Theme.border.selectedWidth : 0
        border.color: Theme.accent
        clip: true
        Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

        // A backup just made fades in
        NumberAnimation on opacity {
            id: _fadeIn
            running: false
            from: 0
            to: 1
            duration: Theme.duration("enter")
            easing: Theme.curve("enter")
        }
        Component.onCompleted: {
            if (row !== null && row.name === root._fadeIn) {
                root._fadeIn = "";
                _fadeIn.start();
            }
        }

        PointerArea {
            id: _rowArea
            centred: false
            anchors.fill: parent
            onClicked: {
                root.forceActiveFocus();
                root.select(_row.opened ? "" : _row.row.name);
            }
        }

        ColumnLayout {
            id: _rowColumn
            x: 12
            y: 8
            width: parent.width - 24
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    objectName: "backupDate"
                    Layout.preferredWidth: Theme.scaled(150)
                    text: _row.row?.date ?? ""
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                    color: Theme.textPrimary
                }
                Text {
                    objectName: "backupReason"
                    Layout.fillWidth: true
                    text: _row.row?.reasonText ?? ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: _row.row?.reason === "" ? Theme.textMuted : Theme.textSecondary
                }
                Rectangle {
                    objectName: "backupKept"
                    visible: _row.row?.kept === true
                    implicitWidth: _keptText.implicitWidth + 14
                    implicitHeight: _keptText.implicitHeight + 4
                    radius: height / 2
                    color: Qt.alpha(Theme.accent, 0.18)
                    border.width: Theme.border.width
                    border.color: Theme.accent
                    Text {
                        id: _keptText
                        anchors.centerIn: parent
                        text: "󰐃 Kept"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.accent
                    }
                }
                Text {
                    objectName: "backupVersion"
                    Layout.preferredWidth: Theme.scaled(110)
                    horizontalAlignment: Text.AlignRight
                    text: (_row.row?.newer ? "⚠ " : "") + (_row.row?.versionText ?? "")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: _row.row?.newer ? Theme.warning
                         : (_row.row?.writtenBy ?? "") === "" ? Theme.textMuted : Theme.textSecondary
                }
            }

            Text {
                objectName: "backupNewer"
                visible: _row.opened && _row.row?.newer === true
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: "⚠ " + (_row.row?.newerLine ?? "")
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.warning
            }
            Text {
                objectName: "backupFile"
                visible: _row.opened
                Layout.fillWidth: true
                text: _row.row?.name ?? ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }
            RowLayout {
                visible: _row.opened
                Layout.fillWidth: true
                spacing: 8
                Text {
                    objectName: "backupPreview"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: _row.opened ? ConfigBackupRules.previewText(root.preview, root.version) : ""
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: _row.opened && (!root.preview?.ok || (root.preview?.failing ?? []).length > 0 || root.preview?.readOnly)
                           ? Theme.warning : Theme.textSecondary
                }
                SmallButton {
                    objectName: "backupApply"
                    visible: _row.row?.readable === true
                    label: "Apply…"
                    tooltip: "Load this backup and restart the shell"
                    onClicked: root.askApply()
                }
                SmallButton {
                    id: _delete
                    objectName: "backupDelete"
                    readonly property string refusal: _row.opened ? root.deleteRefusal(_row.row.name) : ""
                    label: "Delete…"
                    kind: "delete"
                    available: refusal === ""
                    tooltip: refusal !== "" ? refusal : "Delete this backup"
                    onClicked: root.askDelete()
                }
            }
        }
    }
}
