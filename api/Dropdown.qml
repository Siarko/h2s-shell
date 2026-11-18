import QtQuick
import qs.components as Components
import qs.singletons

// The public dropdown (module API 1.5): a choice among `options` — [{ value, label }] —
// shown as a button with the current one's label, or `placeholder` while `value` is none
// of them, opening the list over the content. `picked(value)` reports the choice; the
// owner sets `value`. An option's other fields are not shown, and its label is one line,
// cut when long.
//
//   Dropdown { options: [{ value: "tcp", label: "TCP" }]; value: kind; onPicked: value => kind = value }
//
// `size`: "xs", "s", "m" (the default). A word it does not know shows as the default and
// is logged once (ApiElements).
//
// A wrapper around the internal dropdown (components/Dropdown.qml): what is declared here
// is all a module can rely on. As large as the dropdown inside unless given another size.
Item {
    id: root

    property var options: []
    property alias value: _inner.value
    property string placeholder: "Choose"
    property string size: "m"

    signal picked(var value)

    implicitWidth: _inner.implicitWidth
    implicitHeight: _inner.implicitHeight

    Components.Dropdown {
        id: _inner

        readonly property var sizeWord: ApiElementRules.textSize(root.size)
        onSizeWordChanged: if (!sizeWord.known) ApiElements.unknown("Dropdown", "size", root.size, ApiElementRules.sizeDefault)
        Component.onCompleted: sizeWordChanged()

        width: root.width
        height: root.height
        fontSize: Theme[sizeWord.value]
        options: ApiElementRules.dropdownOptions(root.options)
        placeholder: ApiElementRules.oneLine(root.placeholder)
        onPicked: value => root.picked(value)
    }
}
