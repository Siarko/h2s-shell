import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// The failed settings update in Settings (MigrationFailureNotice): its heading, the parts
// reset to defaults as a list, Keep defaults and Restore previous settings… — all shown at
// once; a session that saves nothing says so (with Start with default settings… when a
// whole-config migration failed). The questions open in the Settings modal, keyed to the
// failure they answer. A restore written but not restarted shows its problem and Restart
// shell.
Rectangle {
    id: root

    // MigrationFailureNotice (MigrationNotice.notice), or a stand-in
    property var notice: null
    // SettingsModalHost, or a stand-in: ask(spec, onAnswer) → "" when it opened
    property var modalHost: null

    readonly property var _current: notice?.current ?? ({ kind: "", parts: [] })
    readonly property bool _readOnly: _current.kind === "readOnly"
    readonly property bool _pending: notice?.restartPending === true

    visible: notice?.entryShown === true
    implicitHeight: visible ? _column.implicitHeight + 24 : 0
    radius: Theme.settings.cardRadius
    color: Qt.alpha(Theme.error, 0.10)
    border.width: Theme.border.selectedWidth
    border.color: Theme.error

    // The question for `what` ("restore", "defaults"), on the failure shown now
    function ask(what) {
        if (!modalHost || !visible)
            return false;
        const spec = what === "restore" ? MigrationNoticeRules.restoreQuestion(_current) : MigrationNoticeRules.defaultsQuestion();
        spec.subject = { key: _current.key };
        return modalHost.ask(spec, answer => {
            if (answer.cancelled)
                return;
            if (answer.button === "restore")
                root.notice.restore(answer.subject.key);
            else if (answer.button === "defaults")
                root.notice.startWithDefaults(answer.subject.key);
        }) === "";
    }

    Connections {
        target: root.notice
        function onAsked(what) {
            root.ask(what);
        }
    }

    ColumnLayout {
        id: _column
        x: 14
        y: 12
        width: parent.width - 28
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: "⚠"
                color: Theme.error
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBodyLarge
            }
            Text {
                objectName: "migrationFailureTitle"
                Layout.fillWidth: true
                text: root._current.summary ?? ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBodyLarge
                font.bold: true
                color: Theme.textPrimary
            }
        }

        Text {
            objectName: "migrationFailureLead"
            Layout.fillWidth: true
            text: root._readOnly ? "Changes are not saved." : "Defaults are used for:"
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textSecondary
        }

        Repeater {
            model: ScriptModel { values: root._readOnly ? [] : (root._current.parts ?? []) }
            Text {
                required property string modelData
                objectName: "migrationFailurePart"
                Layout.fillWidth: true
                Layout.leftMargin: 12
                text: "•  " + modelData
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
            }
        }

        Text {
            objectName: "migrationFailureProblem"
            visible: text !== ""
            Layout.fillWidth: true
            text: root.notice?.problem ?? ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            SmallButton {
                objectName: "migrationKeepDefaults"
                visible: !root._readOnly && !root._pending
                label: "Keep defaults"
                onClicked: root.notice.keepDefaults(root._current.key)
            }
            SmallButton {
                objectName: "migrationRestore"
                visible: !root._readOnly && !root._pending && root.notice?.canRestore === true
                label: "Restore previous settings…"
                kind: "warning"
                onClicked: root.ask("restore")
            }
            SmallButton {
                objectName: "migrationStartDefaults"
                visible: root._readOnly && !root._pending && root._current.startDefaults === true && root.notice?.testRunner !== true
                label: "Start with default settings…"
                kind: "warning"
                onClicked: root.ask("defaults")
            }
            SmallButton {
                objectName: "migrationRestartShell"
                visible: root._pending
                label: "Restart shell"
                kind: "warning"
                onClicked: root.notice.retryRestart()
            }
        }
    }
}
