import QtQuick
import qs.api

// A second element of one module at one place (tests/AnchorsTest.qml): says where it stands
Text {
    id: element

    property var module: null
    property var context: null
    property bool shown: false
    // How often the context was handed over (only when it changes by value)
    property int contextChanges: 0
    onContextChanged: contextChanges += 1

    objectName: "places-a:Second"
    text: "alpha " + (context?.anchor ?? "?") + " " + (context?.placement ?? "?")
    textFormat: Text.PlainText
    font.family: Api.theme.fontFamily
    font.pixelSize: Api.theme.fontSizeSmall
    color: Api.theme.textSecondary
}
