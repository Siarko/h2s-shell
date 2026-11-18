import QtQuick
import QtQuick.Layouts
import qs.singletons

// A section's title within a settings page (System → Network's pages): smaller than the
// page's Heading, bold
Text {
    Layout.topMargin: 16
    Layout.bottomMargin: 6
    textFormat: Text.PlainText
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeBody
    font.bold: true
    color: Theme.textPrimary
}
