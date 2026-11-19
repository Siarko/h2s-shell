import QtQuick
import qs.components as Components
import qs.singletons

// The public pill (module API 1.5): one choice among several, outlined, filled while
// `picked`. `clicked()` reports the click; the owner sets `picked`. `tooltip` says what
// the choice means, under the pointer.
//
//   Pill { label: "Name"; picked: shown === "name"; onClicked: shown = "name" }
//
// `size`: "s", "m" (the default), "l" — the theme's three pill heights. `textSize` (1.32):
// "small" (the default) or "body" — the theme's type sizes, never pixels. A word it does not
// know shows as the default and is logged once (ApiElements).
//
// A wrapper around the internal pill (components/Pill.qml): what is declared here is all
// a module can rely on. As large as the pill inside unless given another size.
Item {
    id: root

    property string label
    property alias picked: _inner.picked
    property alias tooltip: _inner.tooltip
    property string size: "m"
    property string textSize: "small"

    signal clicked

    implicitWidth: _inner.implicitWidth
    implicitHeight: _inner.implicitHeight

    Components.Pill {
        id: _inner

        readonly property var sizeWord: ApiElementRules.pillSize(root.size)
        onSizeWordChanged: if (!sizeWord.known) ApiElements.unknown("Pill", "size", root.size, ApiElementRules.sizeDefault)
        readonly property var textSizeWord: ApiElementRules.pillTextSize(root.textSize)
        onTextSizeWordChanged: if (!textSizeWord.known) ApiElements.unknown("Pill", "textSize", root.textSize, ApiElementRules.pillTextSizeDefault)
        Component.onCompleted: {
            sizeWordChanged();
            textSizeWordChanged();
        }

        width: root.width
        height: root.height
        size: sizeWord.value
        fontSize: Theme[textSizeWord.value]
        label: ApiElementRules.oneLine(root.label)
        onClicked: root.clicked()
    }
}
