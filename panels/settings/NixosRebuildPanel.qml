import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// The side panel of the rebuild of NixOS (in the Settings window's SideDrawer): the three
// steps — "Build, as you", "Your password", "Switch" —, where the run is with its elapsed time
// and progress bar, the outcome, nix's or the root run's last lines with Copy all, and the
// buttons the state offers (NixosRebuildViewRules.controls): Cancel build, Apply now (the one
// control that starts the root run), Apply again, Undo. It only shows NixosRebuild's state and
// passes clicks to the flow (NixosRebuildFlow); the run goes on when the panel closes.
ColumnLayout {
    id: root

    // NixosRebuildFlow (its rebuild, the clicks, the note of a refused click)
    property var flow: null

    readonly property var rebuild: flow?.rebuild ?? null
    readonly property var state: rebuild?.state ?? NixosRebuildRules.initial()
    readonly property var times: rebuild?.times ?? ({ started: 0, built: 0, ended: 0 })
    readonly property var steps: NixosRebuildViewRules.steps(state)
    readonly property var controls: NixosRebuildViewRules.controls(state)
    readonly property var outcome: NixosRebuildViewRules.outcome(state, times)
    readonly property var output: NixosRebuildViewRules.output(state, rebuild?.progress?.lines ?? [], rebuild?.lines ?? [])

    // The clock of the elapsed time: read from the run's own clock, once a second while it counts
    // and the panel shows
    property real _now: rebuild?.clock?.() ?? 0
    readonly property bool _counting: NixosRebuildViewRules.counting(state) && root.visible && (root.Window.window?.visible ?? false)
    on_CountingChanged: if (_counting) _now = rebuild?.clock?.() ?? 0
    Timer {
        interval: 1000
        repeat: true
        running: root._counting
        onTriggered: root._now = root.rebuild?.clock?.() ?? 0
    }
    readonly property string elapsed: NixosRebuildViewRules.duration(NixosRebuildViewRules.elapsedMs(state, times, _now))

    spacing: 10

    function _tone(tone) {
        return tone === "success" ? Theme.success : tone === "warning" ? Theme.warning : tone === "error" ? Theme.error
            : tone === "privileged" ? Theme.privileged : Theme.divider;
    }

    component Label: Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textPrimary
    }
    component Caption: Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.textMuted
    }
    // A boxed piece: the outcome, the output
    component Box: Rectangle {
        default property alias content: _boxColumn.data
        property color edge: Theme.divider
        Layout.fillWidth: true
        implicitHeight: _boxColumn.implicitHeight + 20
        radius: Theme.settings.cardRadius
        color: Theme.surfaceSunken
        border.width: Theme.border.width
        border.color: edge
        ColumnLayout {
            id: _boxColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 6
        }
    }

    // ── The three steps ──
    Repeater {
        model: ScriptModel { values: ["build", "password", "switch"] }
        RowLayout {
            id: stepRow
            required property string modelData
            readonly property var step: root.steps.find(step => step.id === modelData) ?? { label: "", caption: "", mark: "todo" }
            objectName: "rebuild:step:" + modelData
            readonly property string mark: step.mark
            Layout.fillWidth: true
            spacing: 10
            Text {
                Layout.alignment: Qt.AlignTop
                text: stepRow.mark === "stopped" ? String.fromCodePoint(0xF057) : stepRow.mark === "warning" ? String.fromCodePoint(0xF071)
                    : stepRow.mark === "done" ? String.fromCodePoint(0xF058) : stepRow.mark === "current" ? "●" : "○"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: stepRow.mark === "stopped" ? Theme.error : stepRow.mark === "warning" ? Theme.warning
                     : stepRow.mark === "done" ? Theme.success : stepRow.mark === "current" ? Theme.accent : Theme.textMuted
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    objectName: "rebuild:stepLabel:" + stepRow.modelData
                    color: stepRow.mark === "current" || stepRow.mark === "stopped" ? Theme.textPrimary : Theme.textSecondary
                    font.bold: stepRow.mark === "current"
                    text: stepRow.step.label
                }
                Caption {
                    text: stepRow.step.caption
                }
            }
        }
    }

    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.divider }

    // ── Where it is now ──
    RowLayout {
        Layout.fillWidth: true
        Label {
            objectName: "rebuild:phase"
            text: NixosRebuildViewRules.phaseLabel(root.state, root.rebuild?.progress ?? null)
        }
        Caption {
            objectName: "rebuild:elapsed"
            Layout.fillWidth: false
            visible: root.times.started > 0
            text: root.elapsed
        }
    }
    ProgressBar {
        objectName: "rebuild:progress"
        visible: root.controls.progress
        Layout.fillWidth: true
        value: root.state.phase === "building" ? (root.rebuild?.progress?.fraction ?? -1) : -1
    }
    Caption {
        objectName: "rebuild:switching"
        visible: root.controls.switching
        text: NixosRebuildViewRules.texts.switching
    }

    // ── The outcome; Built in … with Apply now ──
    Box {
        objectName: "rebuild:outcome"
        visible: root.outcome.shown
        edge: root._tone(root.outcome.tone)
        color: root.outcome.tone === "error" ? Theme.errorTint : root.outcome.tone === "warning" ? Qt.alpha(Theme.warning, 0.12) : Theme.surfaceSunken
        Label {
            objectName: "rebuild:outcomeText"
            text: root.outcome.text
        }
        Caption {
            objectName: "rebuild:outcomeCaption"
            visible: text !== ""
            text: root.outcome.caption
        }
        RowLayout {
            visible: root.controls.applyNow
            spacing: 6
            PrivilegedMark {
                objectName: "rebuild:applyNowMark"
            }
            SmallButton {
                objectName: "rebuild:applyNow"
                visible: root.controls.applyNow
                label: "Apply now"
                kind: "save"
                tooltip: "Asks for an administrator's password"
                onClicked: root.flow?.applyNow()
            }
        }
    }
    Caption {
        objectName: "rebuild:note"
        visible: text !== ""
        color: Theme.warning
        text: root.flow?.note ?? ""
    }

    // ── nix's or the root run's last lines ──
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        Caption {
            objectName: "rebuild:outputCaption"
            text: root.output.caption
        }
        SmallButton {
            objectName: "rebuild:copyAll"
            label: "Copy all"
            fontSize: Theme.fontSizeSmall
            available: root.output.lines.length > 0
            onClicked: root.flow?.copyLines(root.output.lines)
        }
    }
    Box {
        Repeater {
            model: ScriptModel { values: root.output.shown.map((line, index) => String(index)) }
            Text {
                required property string modelData
                readonly property string line: root.output.shown[Number(modelData)] ?? ""
                objectName: "rebuild:line"
                Layout.fillWidth: true
                text: line
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 4
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: line.startsWith("error") || line.startsWith("Job for") ? Theme.error
                     : line.startsWith("warning") ? Theme.warning : Theme.textSecondary
            }
        }
    }

    // ── The buttons ──
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 6
        SmallButton {
            objectName: "rebuild:cancel"
            visible: root.controls.cancel
            label: "Cancel build"
            kind: "warning"
            onClicked: root.flow?.cancel()
        }
        SmallButton {
            objectName: "rebuild:applyAgain"
            visible: root.controls.applyAgain
            label: "Apply again"
            kind: "save"
            onClicked: root.flow?.applyAgain()
        }
        SmallButton {
            objectName: "rebuild:undo"
            visible: root.controls.undo
            label: "Undo"
            tooltip: "Puts back the shell's previous settings and rebuilds"
            onClicked: root.flow?.undo()
        }
        Item { Layout.fillWidth: true }
    }
    Caption {
        objectName: "rebuild:closing"
        visible: root.controls.closing
        text: NixosRebuildViewRules.texts.closing
    }
}
