import QtQuick
import qs.api

// The fixture's element on a card's name line: wider than the place gives all its elements
// together, so it is cut on the right
Text {
    property var module: null
    property var context: null

    objectName: "anchors-title:Title"
    text: "A wide element on " + (context?.name ?? "?") + " that takes more than the line gives"
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter
    font.family: Api.theme.fontFamily
    font.pixelSize: Api.theme.fontSizeSmall
    color: Api.theme.textSecondary
}
