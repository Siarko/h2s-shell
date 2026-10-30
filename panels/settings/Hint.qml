import QtQuick
import QtQuick.Layouts
import qs.singletons

// Small explanatory text on a settings page, wrapping to the page's width
Text {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSmall
    color: Theme.textMuted
}
