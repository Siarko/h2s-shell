import QtQuick
import qs.singletons

// A progress bar: the part done of `value` (0 to 1) filled over the track, its ends rounded.
// A `value` below 0 is a run of unknown length: a piece of the fill slides along the track
// (standing in the middle with reduced motion). Above 1 is full (Infinity too); not a number
// shows as nothing done.
// Its thickness and its ends come from the theme's `progress` group; `tone` names the fill's
// colour in Theme (the accent by default).
// `wave`: the owner says the bar moves — a lighter band of the fill's colour then passes
// through the filled part once every Theme.duration("progressWave"), as a graph's heartbeat
// (HistoryChart). Whether it runs is ApiElementRules.progressWaves (not full, not of unknown
// length, motion not reduced), and only while the bar is visible.
//
//   ProgressBar { width: parent.width; value: copied / total; wave: copying }
Item {
    id: root

    property real value: 0
    property string tone: "accent"
    property bool wave: false
    // The theme's; a test sets it to see both ways
    property bool reduceMotion: Theme.reduceMotion

    readonly property bool indeterminate: value < 0
    readonly property real _done: isNaN(value) ? 0 : Math.max(0, Math.min(1, value))
    // The sliding piece's share of the track while the length is unknown
    readonly property real _pieceShare: 0.3
    property real _slide: 0.5
    // Only where it is seen: shown, in a shown window, with something filled to run through
    readonly property bool waving: ApiElementRules.progressWaves(wave, value, reduceMotion) && visible
                                   && (Window.window?.visible ?? false) && width * _done > 0
    // 0 → 1 as the band crosses the fill
    property real _wavePhase: 0

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

        // The wave: a band of light, clipped to the fill, fading as it goes. Drawn once; a
        // frame only moves it and changes its opacity
        Item {
            id: _waveClip
            anchors.fill: parent
            clip: true
            visible: root.waving
            readonly property real halfWidth: Math.max(Theme.progress.thickness * 3, width * 0.22)
            readonly property color light: Qt.lighter(_fill.color, 1.6)

            Rectangle {
                objectName: "wave"
                x: -2 * _waveClip.halfWidth + (_waveClip.width + 2 * _waveClip.halfWidth) * root._wavePhase
                width: 2 * _waveClip.halfWidth
                height: parent.height
                opacity: 1 - 0.6 * root._wavePhase
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.alpha(_waveClip.light, 0) }
                    GradientStop { position: 0.5; color: Qt.alpha(_waveClip.light, 0.95) }
                    GradientStop { position: 1.0; color: Qt.alpha(_waveClip.light, 0) }
                }
            }
        }
    }

    NumberAnimation {
        target: root
        property: "_wavePhase"
        from: 0
        to: 1
        duration: Theme.duration("progressWave")
        easing: Theme.curve("progressWave")
        loops: Animation.Infinite
        running: root.waving
        onRunningChanged: if (!running) root._wavePhase = 0
    }

    // There and back along the track, while a run of unknown length shows
    SequentialAnimation {
        running: root.indeterminate && root.visible && !root.reduceMotion
        loops: Animation.Infinite
        onRunningChanged: if (!running) root._slide = 0.5
        NumberAnimation { target: root; property: "_slide"; from: 0; to: 1; duration: Theme.duration("pulse"); easing: Theme.curve("pulse") }
        NumberAnimation { target: root; property: "_slide"; from: 1; to: 0; duration: Theme.duration("pulse"); easing: Theme.curve("pulse") }
    }
}
