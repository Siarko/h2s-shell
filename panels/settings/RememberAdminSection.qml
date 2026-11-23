import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons
import qs.singletons.io

// System → Authentication → Remember the password: after a typed administrator password,
// the shell's next root runs pass without asking for a while (RememberedAdmin). In order:
// the setting "Remember for"; the buttons — Arch: Install / Install again / Remove / Undo,
// one run as administrator each (RememberInstall), built only from what RememberedAdmin read;
// NixOS: the module's option to copy —; one status box: the rule's state, the system's
// length and where it comes from, where the files are, and what is kept now with "Forget
// now". A file changed outside the shell is shown, with "Read again" and "Replace…" (the
// Settings modal, keyed to what it showed). Decisions are RememberViewRules'; nothing here
// asks for a password without a click.
ColumnLayout {
    id: root

    // The I/O, handed in by a suite as stand-ins: the runs and what the last one left
    // (RememberActions: RememberedAdmin.actions), and what is read and kept (its admin:
    // RememberedAdmin's installed, system, facts, files, kept, remembered, forget outcome,
    // refresh, forget, showCountdown, hideCountdown)
    property var actions: RememberedAdmin.actions
    readonly property var admin: actions?.admin ?? null
    // Where questions are asked (SettingsModalHost)
    property var modalHost: null
    property var copyText: text => {
        Quickshell.clipboardText = text;
    }
    property int minutes: Profiles.value("system.rememberAdminMinutes") ?? 5
    // Whether the setting's editor is shown (a suite sets the minutes itself)
    property bool settingShown: true

    Layout.fillWidth: true
    spacing: 0

    readonly property var _installed: admin?.installed ?? null
    readonly property string _system: admin?.system ?? ""
    readonly property var _files: admin?.files ?? null
    readonly property var _facts: admin?.facts ?? null
    readonly property var _remembered: admin?.remembered ?? null
    readonly property var _paths: actions?.installer?.paths ?? RememberInstallRules.livePaths
    readonly property string _backups: _paths?.backups ?? RememberInstallRules.livePaths.backups
    readonly property var lastWrite: actions?.lastWrite ?? null
    readonly property var _actions: RememberViewRules.actions(_installed, _system, _files, minutes, actions?.busy === true, lastWrite)
    // Hand-made files: the rule changed outside the shell, a polkitd.conf not the shell's
    readonly property var _handMade: ({ rule: _installed?.rule === "changed", conf: _installed?.conf === "changed" })
    // What the page says beside the last run's note
    property string _pageNote: ""
    readonly property string note: _pageNote !== "" ? _pageNote : (actions?.note ?? "")
    property bool copied: false

    Component.onCompleted: {
        admin?.refresh();
        _syncCountdown();
    }

    function install() {
        _pageNote = "";
        actions?.install(minutes, null);
    }

    function undo() {
        _pageNote = "";
        actions?.undo();
    }

    function _ask(spec, onAnswer) {
        return !!modalHost && modalHost.ask(spec, onAnswer) === "";
    }

    // Replace…: the files changed by hand the page shows (the conf only where the setting
    // needs the shell's), keyed to the files and the setting as shown
    function askReplace() {
        const replace = { rule: _handMade.rule, conf: RememberViewRules.confInTheWay(_installed, _files, minutes) };
        if (!replace.rule && !replace.conf)
            return;
        _pageNote = "";
        const plan = actions.plan("install", minutes, replace);
        _ask(RememberViewRules.replaceSpec(replace, plan, _handMade, _files, _backups, minutes), answer => {
            if (answer.cancelled || answer.button !== "replace")
                return;
            if (RememberViewRules.subjectHolds(answer.subject, root._files, root.minutes))
                root.actions.install(root.minutes, answer.subject.replace);
            else
                root._pageNote = "Changed since it was shown: nothing replaced.";
        });
    }

    function askRemove() {
        _pageNote = "";
        if (!_actions.remove.asks) {
            actions?.remove(null);
            return;
        }
        const plan = actions.plan("remove", minutes, { rule: true, conf: false });
        _ask(RememberViewRules.removeSpec(plan, _handMade, _files, _backups, minutes), answer => {
            if (answer.cancelled || answer.button !== "remove")
                return;
            if (RememberViewRules.subjectHolds(answer.subject, root._files, root.minutes))
                root.actions.remove(answer.subject.replace);
            else
                root._pageNote = "Changed since it was shown: nothing removed.";
        });
    }

    property real _now: Date.now()
    readonly property var _kept: RememberViewRules.keptRow(_remembered, admin?.kept ?? null,
        { outcome: admin?.forgetOutcome ?? "", reason: admin?.forgetReason ?? "", atMs: admin?.forgetAtMs ?? 0 },
        admin?.lastObtainedMs ?? 0, _now, Qt.formatTime(new Date(admin?.forgetAtMs ?? 0), "hh:mm"))

    // The countdown: once a second while the kept row counts down and the section shows
    readonly property bool _counting: _kept.kept && root.visible && (root.Window.window?.visible ?? false)
    property bool _countdownShown: false
    function _syncCountdown() {
        if (_counting === _countdownShown)
            return;
        _countdownShown = _counting;
        if (_counting)
            admin?.showCountdown();
        else
            admin?.hideCountdown();
    }
    on_CountingChanged: {
        _now = Date.now();
        _syncCountdown();
    }
    on_RememberedChanged: _now = Date.now()
    Component.onDestruction: {
        if (_countdownShown)
            admin?.hideCountdown();
    }
    Timer {
        interval: 1000
        repeat: true
        running: root._counting
        onTriggered: root._now = Date.now()
    }

    function _tone(tone) {
        return tone === "success" ? Theme.success : tone === "warning" ? Theme.warning : tone === "error" ? Theme.error : Theme.textMuted;
    }

    // ── The view ──

    SectionTitle {
        Layout.fillWidth: true
        Layout.topMargin: 18
        text: "Remember the password"
    }
    Hint {
        text: "After you type the administrator password, the shell's next root runs do not ask again for a while."
    }

    // The setting
    SchemaSettingEditor {
        id: _setting
        objectName: "remember:setting"
        readonly property var advice: RememberViewRules.settingHint(root._installed, root.minutes, root._system)
        visible: root.settingShown
        Layout.fillWidth: true
        Layout.topMargin: 10
        key: "system.rememberAdminMinutes"
        editIndex: 0
        hint: advice.text
        hintColor: advice.warning ? Theme.warning : Theme.textMuted
        opacity: (root._installed?.rule ?? "none") === "none" ? 0.5 : 1
    }
    Hint {
        objectName: "remember:settingHint"
        visible: !root.settingShown
        text: _setting.advice.text
    }

    // Arch: Install / Install again / Remove / Undo
    RowLayout {
        visible: root._system === "arch"
        Layout.fillWidth: true
        Layout.topMargin: 12
        spacing: 6
        SmallButton {
            objectName: "remember:install"
            visible: root._actions.install.shown
            label: root._actions.install.label
            kind: "save"
            available: root._actions.available
            tooltip: "Asks the administrator password"
            onClicked: root.install()
        }
        SmallButton {
            objectName: "remember:remove"
            visible: root._actions.remove.shown
            label: "Remove"
            available: root._actions.available
            tooltip: "Asks the administrator password"
            onClicked: root.askRemove()
        }
        SmallButton {
            objectName: "remember:undo"
            visible: root._actions.undo.shown
            label: "Undo"
            available: root._actions.available
            tooltip: "Puts the backed-up files back (asks the administrator password)"
            onClicked: root.undo()
        }
        PrivilegedMark {
            objectName: "remember:mark"
            Layout.leftMargin: 4
            need: "auth"
            remembered: root._remembered
        }
        Item { Layout.fillWidth: true }
    }
    Caption {
        objectName: "remember:caption"
        visible: root._system === "arch"
        Layout.fillWidth: true
        Layout.topMargin: 4
        text: RememberViewRules.backupCaption(root.lastWrite, root._paths)
    }
    Caption {
        objectName: "remember:note"
        visible: text !== ""
        Layout.fillWidth: true
        Layout.topMargin: 2
        color: Theme.warning
        text: root.note
    }

    // NixOS: the module's option to paste
    Rectangle {
        readonly property string line: RememberRules.nixLine(root._facts?.user ?? "", root.minutes)
        visible: root._system === "nixos"
        Layout.fillWidth: true
        Layout.topMargin: 12
        implicitHeight: _nixColumn.implicitHeight + 20
        radius: Theme.settings.cardRadius
        color: Theme.surfaceSunken
        border.width: Theme.border.width
        border.color: Theme.divider
        ColumnLayout {
            id: _nixColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                Caption { Layout.fillWidth: true; text: "Add to your NixOS configuration" }
                SmallButton {
                    objectName: "remember:copy"
                    label: root.copied ? "Copied" : "Copy"
                    fontSize: Theme.fontSizeSmall
                    available: _nixColumn.parent.line !== ""
                    onClicked: {
                        root.copyText(_nixColumn.parent.line);
                        root.copied = true;
                    }
                }
            }
            Text {
                objectName: "remember:nixLine"
                Layout.fillWidth: true
                text: _nixColumn.parent.line
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textPrimary
            }
        }
    }
    Caption {
        objectName: "remember:nixCaption"
        visible: root._system === "nixos"
        Layout.fillWidth: true
        Layout.topMargin: 4
        text: RememberViewRules.nixCaption(root._installed, root.minutes)
    }
    onMinutesChanged: copied = false

    // One status box: the rule, the system's length, where it is written, what is kept now
    Rectangle {
        readonly property string rule: root._installed?.rule ?? ""
        Layout.fillWidth: true
        Layout.topMargin: 12
        implicitHeight: _statusColumn.implicitHeight + 20
        radius: Theme.settings.cardRadius
        color: Theme.fillSubtle
        border.width: Theme.border.width
        border.color: rule === "changed" ? Theme.error : rule === "outdated" ? Theme.warning
                    : root._kept.kept ? Theme.privileged : Theme.outline
        ColumnLayout {
            id: _statusColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; leftMargin: 12; rightMargin: 12 }
            spacing: 10
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 16
                rowSpacing: 6
                Caption { text: "The rule"; wrapMode: Text.NoWrap; Layout.alignment: Qt.AlignTop | Qt.AlignLeft; Layout.topMargin: 2 }
                RowLayout {
                    readonly property var line: RememberViewRules.ruleLine(root._installed)
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 5
                        implicitWidth: 10
                        implicitHeight: 10
                        radius: 5
                        color: root._tone(parent.line.tone)
                    }
                    Label { objectName: "remember:ruleLine"; Layout.fillWidth: true; color: Theme.textPrimary; text: parent.line.text }
                }
                Caption { text: "The system keeps it"; wrapMode: Text.NoWrap; Layout.alignment: Qt.AlignTop | Qt.AlignLeft; Layout.topMargin: 2 }
                Label {
                    objectName: "remember:systemLine"
                    Layout.fillWidth: true
                    color: Theme.textPrimary
                    text: RememberViewRules.systemLine(root._installed, root._system)
                }
                Caption {
                    text: RememberViewRules.writtenTo(root._system, root._installed, root._files, root.minutes).label
                    wrapMode: Text.NoWrap
                    Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                }
                Caption {
                    objectName: "remember:writtenTo"
                    Layout.fillWidth: true
                    text: RememberViewRules.writtenTo(root._system, root._installed, root._files, root.minutes).text
                }
            }
            // While the rule is in: what is kept now, and Forget now
            Rectangle {
                visible: (root._installed?.rule ?? "none") !== "none"
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.divider
            }
            ColumnLayout {
                visible: (root._installed?.rule ?? "none") !== "none"
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: root._kept.kept ? "" : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: root._kept.kept ? Theme.privileged : Theme.textMuted
                    }
                    Label {
                        objectName: "remember:keptLine"
                        Layout.fillWidth: true
                        color: root._kept.kept ? Theme.textPrimary : Theme.textSecondary
                        text: root._kept.text
                    }
                    SmallButton {
                        objectName: "remember:forget"
                        visible: root._kept.forgetShown
                        label: "Forget now"
                        onClicked: root.admin?.forget()
                    }
                }
                Caption {
                    objectName: "remember:problem"
                    visible: text !== ""
                    Layout.leftMargin: 24
                    color: Theme.error
                    text: root._kept.problem
                }
                Hint {
                    visible: text !== ""
                    Layout.leftMargin: 24
                    text: root._kept.hint
                }
            }
        }
    }

    // A file changed outside the shell: its lines, the ones not the shell's marked
    Repeater {
        model: ScriptModel {
            values: root._system !== "arch" ? []
                : [root._installed?.rule === "changed" ? "rule" : "", RememberViewRules.confInTheWay(root._installed, root._files, root.minutes) ? "conf" : ""]
                  .filter(name => name !== "")
        }
        Rectangle {
            id: _hand
            required property string modelData
            readonly property var view: modelData === "rule" ? RememberViewRules.handRule(root._files?.rule, root._facts)
                                                             : RememberViewRules.handConf(root._files?.confs?.[RememberRules.confPath])
            objectName: "remember:hand:" + modelData
            Layout.fillWidth: true
            Layout.topMargin: 6
            implicitHeight: _handColumn.implicitHeight + 24
            radius: Theme.settings.cardRadius
            color: Theme.errorTint
            border.width: Theme.border.width
            border.color: Theme.error
            ColumnLayout {
                id: _handColumn
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Caption {
                        objectName: "remember:handCaption"
                        Layout.fillWidth: true
                        color: Theme.error
                        text: String.fromCodePoint(0xF057) + "  " + _hand.view.caption
                    }
                    SmallButton {
                        objectName: "remember:readAgain"
                        label: "Read again"
                        fontSize: Theme.fontSizeSmall
                        onClicked: root.admin?.refresh()
                    }
                    SmallButton {
                        objectName: "remember:replace"
                        label: "Replace…"
                        kind: "warning"
                        fontSize: Theme.fontSizeSmall
                        available: root._actions.available
                        onClicked: root.askReplace()
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: _fileColumn.implicitHeight + 20
                    radius: Theme.settings.cardRadius
                    color: Theme.surfaceSunken
                    border.width: Theme.border.width
                    border.color: Theme.divider
                    ColumnLayout {
                        id: _fileColumn
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 2
                        Caption {
                            Layout.bottomMargin: 4
                            text: _hand.modelData === "rule" ? RememberRules.rulePath : RememberRules.confPath
                        }
                        Repeater {
                            model: ScriptModel { values: _hand.view.lines.map((line, i) => String(i)) }
                            RowLayout {
                                id: _fileLine
                                required property string modelData
                                readonly property var line: _hand.view.lines[Number(modelData)] ?? ({ text: "", marked: false })
                                Layout.fillWidth: true
                                spacing: 8
                                Text {
                                    objectName: _fileLine.line.marked ? "remember:marked" : _fileLine.line.more ? "remember:more" : "remember:line"
                                    Layout.fillWidth: true
                                    text: _fileLine.line.text
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: _fileLine.line.marked ? Theme.error : _fileLine.line.more ? Theme.textMuted : Theme.textSecondary
                                }
                                Caption { visible: _fileLine.line.marked; text: "not the shell's"; color: Theme.error; wrapMode: Text.NoWrap }
                            }
                        }
                    }
                }
                Caption {
                    Layout.fillWidth: true
                    text: "Replace puts the hand-made file in " + root._backups + " first."
                }
            }
        }
    }

    // ── Pieces ──

    component Caption: Text {
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textMuted
        wrapMode: Text.WordWrap
    }
    component Label: Text {
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textSecondary
        wrapMode: Text.WordWrap
    }
}
