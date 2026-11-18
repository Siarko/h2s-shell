import QtQuick
import QtQuick.Layouts
import qs.singletons

// The public notice (module API 1.6): a line that says what needs the user, or what went
// well, as the line on a network's card does. Small, wrapping to the width it is given.
//
//   Notice { text: "The key expires in 3 days" }
//   Notice { kind: "success"; text: "Sent" }
//
// `kind`: "warning" (the default), "danger", "success". A word it does not know shows as
// the default and is logged once (ApiElements).
//
// What is declared here is all a module can rely on. It fills the width a layout gives it.
Item {
    id: root

    property alias text: _line.text
    property string kind: "warning"

    Layout.fillWidth: true
    implicitWidth: _line.implicitWidth
    implicitHeight: _line.implicitHeight

    Text {
        id: _line

        readonly property var kindWord: ApiElementRules.noticeKind(root.kind)
        onKindWordChanged: if (!kindWord.known) ApiElements.unknown("Notice", "kind", root.kind, ApiElementRules.noticeKindDefault)
        Component.onCompleted: kindWordChanged()

        width: root.width
        wrapMode: Text.WordWrap
        // A module's words, often with a device's or a network's name in them
        textFormat: Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme[kindWord.value]
    }
}
