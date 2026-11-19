import QtQuick
import qs.api

// An element at an anchor (tests/AnchorsTest.qml): says where it stands
Text {
    id: element

    property var module: null
    property var context: null
    property bool shown: false
    // How often the context was handed over (only when it changes by value)
    property int contextChanges: 0
    onContextChanged: contextChanges += 1

    objectName: "anchors-a:Element"
    text: "alpha " + (context?.anchor ?? "?") + " " + (context?.placement ?? "?")
    textFormat: Text.PlainText
    font.family: Api.theme.fontFamily
    font.pixelSize: Api.theme.fontSizeSmall
    color: Api.theme.textSecondary
}
