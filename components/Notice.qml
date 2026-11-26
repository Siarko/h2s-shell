import QtQuick
import QtQuick.Layouts
import qs.singletons

// A line that says what needs the user, or what went well, as the line on a network's
// card does: small, wrapping to the width it is given, in the colour of its `kind` —
// "warning" (the default), "danger", "success" (ApiElementRules.noticeKinds; a word it does
// not know shows as the default).
//
//   Notice { text: "The key expires in 3 days" }
//   Notice { kind: "success"; text: "Sent" }
Text {
    property string kind: "warning"

    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    // Often with a device's or a network's name in it
    textFormat: Text.PlainText
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSmall
    color: Theme[ApiElementRules.noticeKind(kind).value]
}
