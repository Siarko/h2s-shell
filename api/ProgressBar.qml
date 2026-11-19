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
// A wrapper around the internal bar (components/ProgressBar.qml): what is declared here is
// all a module can rely on. It fills the width a layout gives it.
Item {
    id: root

    property real value: 0
    property string kind: "normal"

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
        tone: kindWord.value
    }
}
