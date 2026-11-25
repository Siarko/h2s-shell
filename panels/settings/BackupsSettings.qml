import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// System → Backups: the config backups (ConfigBackupList, read each time the page shows),
// newest first — the date, why it was made (a manual one marked Kept: never pruned), the
// version that wrote it (a newer writer marked). A row clicked opens: the file's name, a newer
// writer's one line, what Apply would do (its preview, run in memory) and Apply…, whose
// question in the Settings modal is a steps list keyed to the backup and what it holds.
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
    // Why the last Apply did not start ("" none)
    property string problem: ""

    readonly property var _rows: backups?.rows ?? []
    readonly property var _selectedRow: _rows.find(row => row.name === selected) ?? null

    // A row that went (deleted, pruned) closes
    on_RowsChanged: {
        if (selected !== "" && !_rows.some(row => row.name === selected))
            select("");
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

        PointerArea {
            id: _rowArea
            centred: false
            anchors.fill: parent
            onClicked: root.select(_row.opened ? "" : _row.row.name)
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
            }
            Text {
                objectName: "backupProblem"
                visible: _row.opened && root.problem !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.problem
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
            }
        }
    }
}
