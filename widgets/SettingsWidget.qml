import QtQuick
import qs.components
import qs.singletons

BarWidget {
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
