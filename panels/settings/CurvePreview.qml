import QtQuick
import qs.singletons

// The Curves page's preview: a square moving with the curve being edited and, when there
// is one, another with the curve compared with — time running 0 to 1 at a steady pace,
// over and over, each square applying its curve. `time` is that moment, for the graph's
// dots to follow.
Item {
    id: root

    property var draftEasing: null
    property var compareEasing: null
    property int duration: 800
    property real time: 0

    implicitHeight: compareEasing ? 64 : 32

    SequentialAnimation {
        running: root.visible
        loops: Animation.Infinite
        // Restarts with a new duration
        property var _restartOn: root.duration
        on_RestartOnChanged: if (running) restart()
        PropertyAction { target: root; property: "time"; value: 0 }
        PauseAnimation { duration: 300 }
        NumberAnimation {
            target: root
            property: "time"
            from: 0
            to: 1
            duration: root.duration
        }
        PauseAnimation { duration: 500 }
    }

    component Track: Item {
        id: _track
        property var easing
        property color squareColor
        width: root.width
        height: 28

        // Its own sampler, bound rather than set: setting a shared one from a binding made
        // the binding loop. Through the id, not `parent`: an animation has no parent, and
        // the name reached the Column holding the track — no easing there, so every track
        // moved with the draft.
        NumberAnimation { id: _trackSampler; easing: _track.easing ?? root.draftEasing }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 2
            color: Theme.track
        }
        Rectangle {
            width: 24
            height: 24
            radius: 5
            anchors.verticalCenter: parent.verticalCenter
            color: _track.squareColor
            // Overshoot carries it past the ends, as the animation would
            x: _trackSampler.easing.valueForProgress(root.time) * (parent.width - width)
        }
    }

    Column {
        spacing: 8
        Track { easing: root.draftEasing; squareColor: Theme.accent }
        Track {
            visible: root.compareEasing !== null
            easing: root.compareEasing ?? root.draftEasing
            squareColor: Theme.textMuted
        }
    }
}
