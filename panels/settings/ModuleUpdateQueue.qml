import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// Settings → Modules, the update queue: its title line
// ("Updating" / "Updates finished", "2 of 3", and once it has ended an "×" that closes the
// list), one row per module (ModuleUpdateRules.rowText, a waving bar while it downloads,
// "Review" on a row waiting for approval) and, once the whole queue has ended, the one offer to
// restart the shell for the modules whose new files need it — "Restart shell" (always the
// user's click) or "Later" (the offer goes; Settings keeps a banner until the restart).
SettingsSection {
    id: root

    // The updater (queue, queueSummary, restartOffer, dismissRestartOffer())
    property var updater: null
    // "Restart shell"
    signal restartRequested
    // "Review" on a row waiting for approval: its module's card
    signal reviewRequested(string id)

    // The queue's run the user closed (its lastRun): closed until another run
    property var _closedRun: null
    readonly property var queue: updater?.queue ?? ({ rows: [], ended: true })
    readonly property var summary: ModuleUpdateRules.queueSummary(queue)
    readonly property bool listShown: (queue.rows ?? []).length > 0 && _closedRun !== queue.lastRun
    readonly property alias restartButton: _restart

    anchor: "queue"
    visible: listShown || updater?.restartOffer
    title: listShown ? summary.title + " · " + summary.count : "Restart needed"
    spacing: 4

    buttons: SmallButton {
        objectName: "closeQueue"
        visible: root.listShown && root.queue.ended === true
        label: "×"
        tooltip: "Close — a pending restart stays at the top of Settings"
        onClicked: {
            root._closedRun = root.queue.lastRun;
            if (root.updater?.restartOffer)
                root.updater.dismissRestartOffer();
        }
    }

    KeyedModel { id: _rows; values: root.listShown ? (root.queue.rows ?? []) : []; keyProp: "id" }
    Repeater {
        model: _rows.model
        RowLayout {
            id: _row
            required property string modelData
            readonly property var row: _rows.byKey[modelData] ?? ({ id: "", phase: "" })
            objectName: "queueRow"
            Layout.fillWidth: true
            spacing: 10
            Text {
                objectName: "queueRowText"
                Layout.fillWidth: true
                text: ModuleUpdateRules.rowText(_row.row)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: _row.row.phase === "failed" ? Theme.error : _row.row.phase === "approval" || _row.row.phase === "notFinished" ? Theme.warning
                     : _row.row.phase === "done" ? Theme.success : Theme.textSecondary
            }
            ProgressBar {
                objectName: "queueBar"
                visible: _row.row.phase === "downloading"
                Layout.preferredWidth: Math.round(root.width * 0.25)
                value: typeof _row.row.progress?.percent === "number" ? _row.row.progress.percent / 100 : -1
                wave: typeof _row.row.progress?.percent === "number"
            }
            SmallButton {
                objectName: "reviewButton"
                visible: _row.row.phase === "approval"
                label: "Review"
                kind: "warning"
                onClicked: root.reviewRequested(_row.row.id)
            }
        }
    }

    // The one restart offer, once the queue has ended
    RowLayout {
        objectName: "restartOffer"
        visible: !!root.updater?.restartOffer
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 6
        Text {
            Layout.fillWidth: true
            text: root.updater?.restartOffer?.text ?? ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.warning
        }
        SmallButton {
            id: _restart
            objectName: "restartShell"
            label: "Restart shell"
            kind: "warning"
            onClicked: root.restartRequested()
        }
        SmallButton {
            objectName: "restartLater"
            label: "Later"
            onClicked: root.updater.dismissRestartOffer()
        }
    }
}
