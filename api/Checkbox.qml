import QtQuick
import qs.components as Components
import qs.singletons

// The public checkbox (module API 1.5): a box with an optional `label` beside it. A click
// on either, or Space while it has the focus, gives `toggled()`; the owner flips
// `checked`, so the box can follow state kept elsewhere.
//
//   Checkbox { label: "Funnel"; checked: funnel; onToggled: funnel = !funnel }
//
// A wrapper around the internal checkbox (components/Checkbox.qml): what is declared here
// is all a module can rely on. As large as the checkbox inside unless given another size.
Item {
    id: root

    property string label
    property alias checked: _inner.checked

    signal toggled

    implicitWidth: _inner.implicitWidth
    implicitHeight: _inner.implicitHeight

    Components.Checkbox {
        id: _inner

        width: root.width
        height: root.height
        label: ApiElementRules.oneLine(root.label)
        onToggled: root.toggled()
    }
}
