import QtQuick
import QtQuick.Layouts
import qs.components
import qs.singletons

// A notification card's progress bar (NotificationCard): how far the sender's job has gone
// (the card's `progress`, from its hints), shown as the card's `progressView` says, and its
// wave.
ProgressBar {
    id: root

    // The card it is the bar of (NotificationCard)
    required property Item card

    // The wave: while the job runs and its value grew lately (NotificationRules.progressWave).
    // A sender updates the same notification as its job goes; a value that stands still (a
    // stall) lets the wave stop on its own.
    readonly property bool grewLately: NotificationRules.progressWave(card.progress.state, _grewAt, _waveNow, card.progressWaveMs)
    property double _grewAt: 0
    property double _waveNow: 0
    // Whose value the last one is: another notification in the card starts again
    property var _waveFor: null
    // The last value the bar showed; NaN while it showed none (the first value is no growth)
    property real _lastValue: NaN

    // A new notification in the card: its first value is no growth
    function startAgain() {
        _waveFor = card.notification;
        _grewAt = 0;
        _lastValue = NaN;
        _waveEnd.stop();
    }

    objectName: "progress"
    visible: card.progressView.bar
    Layout.fillWidth: true
    Layout.topMargin: 4
    value: card.progress.value
    tone: card.progress.tone
    wave: grewLately

    Connections {
        target: root.card

        function onProgressChanged() {
            const progress = root.card.progress;
            const value = progress.shown ? progress.value : NaN;
            if (root.card.notification !== root._waveFor) {
                root._waveFor = root.card.notification;
                root._grewAt = 0;
                _waveEnd.stop();
            } else if (progress.state === "running" && value > root._lastValue) {
                root._grewAt = Date.now();
                root._waveNow = root._grewAt;
                _waveEnd.interval = root.card.progressWaveMs;
                _waveEnd.restart();
            }
            root._lastValue = value;
        }
    }

    Component.onCompleted: {
        _waveFor = card.notification;
        _lastValue = card.progress.shown ? card.progress.value : NaN;
    }

    // When the window after the last growth has passed; a timer that fires early waits on
    Timer {
        id: _waveEnd
        onTriggered: {
            root._waveNow = Date.now();
            const left = root._grewAt + root.card.progressWaveMs - root._waveNow;
            if (left > 0) {
                interval = left;
                restart();
            }
        }
    }
}
