import QtQuick
import QtQuick.Layouts
import qs.components as Components
import qs.singletons

// The public progress bar (module API 1.31): how much of something is done, `value` from 0
// to 1 (outside that, the nearer end; not a number, nothing done). A value below 0 is a run
// of unknown length: a piece of the fill slides along the track.
//
//   ProgressBar { value: sent / total }
//   ProgressBar { kind: "success"; value: 1 }
//
// `kind`: "normal" (the default: the accent), "success", "warning", "danger". A word it
// does not know shows as the default and is logged once (ApiElements). Its thickness and
// its ends are the theme's (Api.theme.progress).
//
// `wave` (1.35, false by default): the owner says the bar is moving now — a band of light
// then passes through the filled part every Theme.duration("progressWave"); none while full,
// of unknown length, hidden, or with reduced motion (ApiElementRules.progressWaves). The bar
// does not judge that itself: a stalled job sets it false.
//
//   ProgressBar { value: sent / total; wave: sending && !stalled }
//
// A wrapper around the internal bar (components/ProgressBar.qml): what is declared here is
// all a module can rely on. It fills the width a layout gives it.
Item {
    id: root

    property real value: 0
    property string kind: "normal"
    property bool wave: false

    Layout.fillWidth: true
    implicitWidth: _inner.implicitWidth
    implicitHeight: _inner.implicitHeight

    Components.ProgressBar {
        id: _inner

        readonly property var kindWord: ApiElementRules.progressKind(root.kind)
        onKindWordChanged: if (!kindWord.known) ApiElements.unknown("ProgressBar", "kind", root.kind, ApiElementRules.progressKindDefault)
        Component.onCompleted: kindWordChanged()

        width: root.width
        height: root.height
        value: root.value
        wave: root.wave
        tone: kindWord.value
    }
}
