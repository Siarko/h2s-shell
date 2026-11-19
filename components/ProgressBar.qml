import QtQuick
import qs.singletons

// A progress bar: the part done of `value` (0 to 1) filled over the track, its ends rounded.
// A `value` below 0 is a run of unknown length: a piece of the fill slides along the track
// (standing in the middle with reduced motion). Anything not a number shows as nothing done.
// Its thickness and its ends come from the theme's `progress` group; `tone` names the fill's
// colour in Theme (the accent by default).
//
//   ProgressBar { width: parent.width; value: copied / total }
Item {
    id: root

    property real value: 0
    property string tone: "accent"

    readonly property bool indeterminate: value < 0
    readonly property real _done: Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0
    // The sliding piece's share of the track while the length is unknown
    readonly property real _pieceShare: 0.3
    property real _slide: 0.5

    implicitHeight: Theme.progress.thickness

    Rectangle {
        id: _track
        anchors.fill: parent
        radius: Math.min(Theme.progress.radius, height / 2)
        color: Theme.track
    }

    Rectangle {
        id: _fill
        readonly property real pieceWidth: root.width * root._pieceShare
        x: root.indeterminate ? (root.width - pieceWidth) * root._slide : 0
        width: root.indeterminate ? pieceWidth : root.width * root._done
        height: parent.height
        radius: _track.radius
        color: Theme[root.tone] ?? Theme.accent
        Behavior on width {
            enabled: !root.indeterminate
            NumberAnimation { duration: Theme.duration("value"); easing: Theme.curve("value") }
        }
    }

    // There and back along the track, while a run of unknown length shows
    SequentialAnimation {
        running: root.indeterminate && root.visible && !Theme.reduceMotion
        loops: Animation.Infinite
        onRunningChanged: if (!running) root._slide = 0.5
        NumberAnimation { target: root; property: "_slide"; from: 0; to: 1; duration: Theme.duration("pulse"); easing: Theme.curve("pulse") }
        NumberAnimation { target: root; property: "_slide"; from: 1; to: 0; duration: Theme.duration("pulse"); easing: Theme.curve("pulse") }
    }
}
