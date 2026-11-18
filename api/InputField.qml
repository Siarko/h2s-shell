import QtQuick
import qs.components as Components
import qs.singletons

// The public text field (module API 1.5): one line of text in a box, `placeholder` while
// it is empty, red around it while `problem` (the value is wrong now). `password` hides
// the text, with an eye that shows it: `revealed` says whether it shows, the eye flips it
// and `revealToggled()` says so. `accepted()` is Return, `textEdited()` a change made by
// typing, `editingFinished()` Return or the focus leaving.
//
//   InputField { placeholder: "Name"; onAccepted: save(text) }
//
// `size`: "xs", "s", "m" (the default). A word it does not know shows as the default and
// is logged once (ApiElements).
//
// A wrapper around the internal field (components/InputField.qml): what is declared here
// is all a module can rely on. As large as the field inside unless given another size.
Item {
    id: root

    property alias text: _inner.text
    property alias placeholder: _inner.placeholder
    property alias problem: _inner.problem
    property alias password: _inner.password
    property alias revealed: _inner.revealed
    property string size: "m"

    signal accepted
    signal textEdited
    signal editingFinished
    signal revealToggled

    implicitWidth: _inner.implicitWidth
    implicitHeight: _inner.implicitHeight

    Components.InputField {
        id: _inner

        readonly property var sizeWord: ApiElementRules.textSize(root.size)
        onSizeWordChanged: if (!sizeWord.known) ApiElements.unknown("InputField", "size", root.size, ApiElementRules.sizeDefault)
        Component.onCompleted: sizeWordChanged()

        width: root.width
        height: root.height
        fontSize: Theme[sizeWord.value]
        onAccepted: root.accepted()
        onTextEdited: root.textEdited()
        onEditingFinished: root.editingFinished()
        onRevealToggled: root.revealToggled()
    }
}
