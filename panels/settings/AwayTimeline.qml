import QtQuick
import Quickshell
import QtQuick.Layouts
import qs.components
import qs.singletons

// What happens when you are away, as a line from your last input: one lane, or one per
// monitor, each with its stretches (the desktop, the screensaver, off, asleep); the lock one
// line across every lane, the sleep another (the whole computer), the commands' moment a
// grey one; a sleep long after the rest on a compressed tail after a break "≈"
// (AwayViewRules.axis); the times as labels above the lanes,
// or below where they would touch (AwayViewRules.placeLabels); one line under it. Always
// drawn at its full height: with nothing on it is empty and dimmed, and an app keeping
// the screen on dims it and takes the line under it.
ColumnLayout {
    id: root

    // The lanes: [{ key, name, times: { saverAfter, screenOffAfter } }]; names shown while
    // `perMonitor`
    property var lanes: []
    property bool perMonitor: false
    // Seconds; 0 = no idle lock
    property int lockAfter: 0
    // The commands' moment (seconds), -1 while they do not run
    property int commandsAt: -1
    // Seconds; 0 = no sleep after idle
    property int sleepAfter: 0
    // logind's sleep blocks as last read, [{ who, why }] (Idle.sleepBlockers)
    property var sleepBlockers: []
    property int lockedScreenOffAfter: 0
    property bool canPowerOff: true
    // [{ who, why }] (Idle.holders)
    property var holders: []

    readonly property var _times: lanes.map(lane => lane.times)
    readonly property bool anything: AwayViewRules.anything(_times, lockAfter, sleepAfter)
    readonly property real laneLabelWidth: perMonitor ? 150 : 0
    readonly property real trackWidth: Math.max(1, width - laneLabelWidth)
    // { end, breakAt, sleepAt } (seconds)
    readonly property var axis: AwayViewRules.axis(_times, lockAfter, commandsAt, sleepAfter)
    readonly property int axisEnd: axis.end
    readonly property string caption: AwayViewRules.caption({
        holders: holders, sleepBlockers: sleepBlockers, anything: anything, lockAfter: lockAfter, sleepAfter: sleepAfter,
        perMonitor: perMonitor, lockedScreenOffAfter: lockedScreenOffAfter, canPowerOff: canPowerOff
    }, seconds => Format.duration(seconds))

    function xOf(t) {
        return trackWidth * AwayViewRules.place(t, axis);
    }

    readonly property var marks: AwayViewRules.marks(_times, lockAfter, commandsAt, seconds => Format.duration(seconds), canPowerOff, sleepAfter)
    // Each mark's label where it goes: [{ text, kind, left, row }]
    readonly property var labels: {
        const placed = AwayViewRules.placeLabels(marks.map(mark => ({
            x: xOf(mark.t),
            width: (mark.kind === "lock" || mark.kind === "sleep" ? _boldMetrics : _metrics).advanceWidth(mark.text)
        })), trackWidth);
        return marks.map((mark, index) => Object.assign({}, mark, placed[index]));
    }

    readonly property real labelHeight: _metrics.height

    function _kindWord(kind) {
        return ({ on: "Desktop", saver: "Screensaver", off: "Off", asleep: "Asleep" })[kind] ?? "";
    }

    spacing: 2

    FontMetrics {
        id: _metrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }
    FontMetrics {
        id: _boldMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.bold: true
    }

    // One side's labels: 0 above the lanes, 1 below
    component LabelRow: Item {
        id: _labelRow
        required property int row
        // The timeline (an inline component sees nothing of the file's ids)
        required property Item timeline
        Layout.fillWidth: true
        implicitHeight: timeline.labelHeight

        Repeater {
            model: ScriptModel {
                values: _labelRow.timeline.labels.map((label, index) => String(index)).filter(index => _labelRow.timeline.labels[Number(index)].row === _labelRow.row)
            }

            Text {
                required property string modelData
                readonly property var label: _labelRow.timeline.labels[Number(modelData)] ?? { text: "", kind: "time", left: 0 }
                objectName: "timelineLabel"
                x: _labelRow.timeline.laneLabelWidth + label.left
                text: label.text
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: label.kind === "lock" || label.kind === "sleep"
                color: label.kind === "lock" ? Theme.accent : label.kind === "sleep" ? Theme.textPrimary : Theme.textSecondary
            }
        }
    }

    LabelRow { row: 0; timeline: root }

    // The lanes; lanes added or taken away (per monitor on or off) slide
    Item {
        id: _lanesArea
        Layout.fillWidth: true
        implicitHeight: _lanesColumn.implicitHeight
        clip: true
        property bool _ready: false
        Component.onCompleted: Qt.callLater(() => _ready = true)
        Behavior on implicitHeight {
            enabled: _lanesArea._ready
            NumberAnimation { duration: Theme.duration("expand"); easing: Theme.curve("expand") }
        }

        Column {
            id: _lanesColumn
            width: parent.width
            spacing: 4
            opacity: !root.anything ? 0.45 : root.holders.length > 0 ? 0.4 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.duration("fade") } }

            Repeater {
                model: ScriptModel { values: root.lanes.map(lane => lane.key) }

                Item {
                    id: _lane
                    required property string modelData
                    readonly property var lane: root.lanes.find(entry => entry.key === modelData) ?? { name: "", times: {} }
                    readonly property var stretches: AwayViewRules.segments(lane.times, root.axisEnd, root.canPowerOff,
                                                                            root.sleepAfter, root.axis.breakAt)
                    objectName: "timelineLane"
                    width: _lanesColumn.width
                    height: 26

                    Text {
                        visible: root.perMonitor
                        width: root.laneLabelWidth - 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: _lane.lane.name
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.textSecondary
                    }

                    Item {
                        x: root.laneLabelWidth
                        width: root.trackWidth
                        height: parent.height

                        Repeater {
                            model: ScriptModel { values: _lane.stretches.map((stretch, index) => String(index)) }

                            Rectangle {
                                required property string modelData
                                readonly property var stretch: _lane.stretches[Number(modelData)] ?? { from: 0, to: 0, kind: "on" }
                                x: root.xOf(stretch.from)
                                width: Math.max(0, root.xOf(stretch.to) - root.xOf(stretch.from) - 2)
                                height: parent.height
                                radius: Theme.settings.cardRadius
                                color: stretch.kind === "on" ? Theme.fillSubtle : stretch.kind === "saver" ? Theme.accentTint
                                     : stretch.kind === "asleep" ? Theme.surfaceSunken : Theme.overlayOpaque
                                border.width: Theme.border.width
                                border.color: Theme.outline

                                Text {
                                    anchors.centerIn: parent
                                    visible: implicitWidth + 8 < parent.width
                                    text: root._kindWord(parent.stretch.kind)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: parent.stretch.kind === "saver" ? Theme.textPrimary
                                         : parent.stretch.kind === "on" ? Theme.textSecondary : Theme.textMuted
                                }
                            }
                        }
                    }
                }
            }
        }

        // The commands' moment: a grey line across the lanes
        Rectangle {
            visible: root.commandsAt > 0
            x: root.laneLabelWidth + root.xOf(root.commandsAt) - 1
            width: 2
            height: parent.height
            color: Theme.textSecondary
            opacity: 0.8
        }

        // The sleep: the whole computer, a line across every lane
        Rectangle {
            objectName: "timelineSleep"
            visible: root.sleepAfter > 0
            x: root.laneLabelWidth + root.xOf(root.sleepAfter) - 1
            width: 2
            height: parent.height
            color: Theme.textPrimary
        }

        // The break before a compressed tail
        Text {
            objectName: "timelineBreak"
            visible: root.axis.breakAt > 0
            x: root.laneLabelWidth + root.xOf(root.axis.breakAt) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            text: "≈"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            font.bold: true
            color: Theme.textPrimary
        }

        // The idle lock: one for the session, a line across every lane
        Rectangle {
            objectName: "timelineLock"
            visible: root.lockAfter > 0
            x: root.laneLabelWidth + root.xOf(root.lockAfter) - 1
            width: 2
            height: parent.height
            color: Theme.accent
        }
    }

    LabelRow { row: 1; timeline: root }

    // One line, always there: what the lock does, nothing at all, or who keeps the screen on
    Text {
        objectName: "timelineCaption"
        Layout.fillWidth: true
        Layout.topMargin: 2
        text: root.caption
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: root.holders.length > 0 || root.sleepAfter > 0 && root.sleepBlockers.length > 0 ? Theme.warning : Theme.textMuted
    }
}
