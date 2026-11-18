import QtQuick
import QtQuick.Layouts
import qs.components as Components

// The public row (module API 1.6): one line of a settings page, a card or a popup — a
// `label`, a short line under it on what it is about (`hint`), and on the right a
// `value`, controls, or both. The controls are its children, written inside it; they
// stand in a row.
//
//   SettingsRow { label: "Port"; hint: "Where others reach it"; InputField { … } }
//   SettingsRow { label: "Address"; value: address }
//
// A wrapper around the internal row (components/SettingsRow.qml): what is declared here
// is all a module can rely on (`controls` is where the children go, nothing to set). It
// fills the width a layout gives it.
Item {
    id: root

    property alias label: _inner.label
    property alias hint: _inner.hint
    property alias value: _inner.value
    default property alias controls: _inner.controls

    Layout.fillWidth: true
    implicitWidth: _inner.implicitWidth
    implicitHeight: _inner.implicitHeight

    Components.SettingsRow {
        id: _inner

        width: root.width
        height: root.height
    }
}
