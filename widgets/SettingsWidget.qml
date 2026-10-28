import QtQuick
import qs.components
import qs.singletons

BarWidget {
    widgetType: "settings"
    property var settingsWindow: null

    onClicked: settingsWindow.visible = !settingsWindow.visible

    Text {
        text: "⚙"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeXLargeDisplay
        color: Theme.textPrimary
        anchors.centerIn: parent
    }
}
