import QtQuick
import qs.api

// No button: a card's buttons refuse it (the region takes the public SmallButton only)
Text {
    property var module: null
    property var context: null

    objectName: "anchors-buttons:NotButton"
    text: "not a button"
    textFormat: Text.PlainText
    font.family: Api.theme.fontFamily
    font.pixelSize: Api.theme.fontSizeSmall
    color: Api.theme.textSecondary
}
