import QtQuick
import qs.components
import qs.singletons

BarWidget {
    widgetType: "settings"

    // The one settings window lives in shell.qml, not on each screen's bar
    onClicked: Shell.toggleSettings()

    // A Nerd Font glyph, like the other bar icons: "⚙" is missing from the font, and the
    // fallback font that draws it sat below the middle of the cell
    Text {
        text: "󰒓"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeTitle
        color: Theme.textPrimary
        anchors.centerIn: parent
        // The 27 px text box in the 30 px cell centres half a pixel high, which this glyph
        // makes visible; measured with TextMetrics, the ink itself is centred in the box
        anchors.verticalCenterOffset: 1
    }
}
