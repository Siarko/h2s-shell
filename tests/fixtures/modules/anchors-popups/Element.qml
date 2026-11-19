import QtQuick
import qs.api

// An element in the shell's popups (tests/AnchorsTest.qml): says where it stands
Text {
    property var module: null
    property var context: null
    property bool shown: false
    property int contextChanges: 0

    objectName: "anchors-popups:Element"
    text: "popups Element " + (context?.anchor ?? "?") + " " + (context?.placement ?? "?")
    textFormat: Text.PlainText
    font.family: Api.theme.fontFamily
    font.pixelSize: Api.theme.fontSizeSmall
    color: Api.theme.textSecondary
    onContextChanged: contextChanges++
}
