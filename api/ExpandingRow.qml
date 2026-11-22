import QtQuick
import QtQuick.Layouts
import qs.components as Components
import qs.singletons

// The public row that opens (module API 1.6): a `label`, a short line under it (`hint`)
// and the mark of a card's header; a click anywhere on the line flips `open`. What it
// opens is its one child, written inside it: built when the row opens, destroyed once it
// has slid shut — nothing of it exists while the row is closed — and as wide as the row.
//
//   ExpandingRow { label: "Exit node"; hint: current; ColumnLayout { … } }
//
// A wrapper around the internal row (components/ExpandingRow.qml): what is declared here
// is all a module can rely on (`content` is where the child goes, nothing to set). It
// fills the width a layout gives it.
Item {
    id: root

    property string label
    property alias hint: _inner.hint
    property alias open: _inner.open
    default property alias content: _inner.content

    Layout.fillWidth: true
    implicitWidth: _inner.implicitWidth
    implicitHeight: _inner.implicitHeight

    Components.ExpandingRow {
        id: _inner

        width: root.width
        height: root.height
        label: ApiElementRules.oneLine(root.label)
    }
}
