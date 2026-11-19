import QtQuick
import qs.api

// An element on the shell's General page (tests/AnchorsTest.qml): says where it stands
Text {
    property var module: null
    property var context: null
    property bool shown: false

    objectName: "anchors-general:Element"
    text: "general Element " + (context?.anchor ?? "?") + " " + (context?.placement ?? "?")
    textFormat: Text.PlainText
    font.family: Api.theme.fontFamily
    font.pixelSize: Api.theme.fontSizeSmall
    color: Api.theme.textSecondary
}
