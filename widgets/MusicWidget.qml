import QtQuick
import qs.components
import qs.singletons

PopupWidget {
    widgetType: "music"

    onMiddleClicked: Music.togglePlay()
    onScrollNotch: delta => {
        if (delta > 0)
            Music.next();
        else
            Music.previous();
    }

    BarRow {
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: Music.playing ? "󰐊" : "󰏤"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            color: Theme.textPrimary
            visible: Music.hasPlayer
        }

        BarText {
            text: Music.hasPlayer ? (Music.activePlayer.identity || "Player") : "󰎈"
            font.family: Theme.fontFamily
            font.pixelSize: Music.hasPlayer ? Theme.fontSizeMedium : Theme.fontSizeHeading
            color: Theme.textPrimary
            elide: Text.ElideRight
        }
    }
}
