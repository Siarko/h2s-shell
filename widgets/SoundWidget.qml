import QtQuick
import qs.components
import qs.singletons

PopupWidget {
    widgetType: "sound"

    onMiddleClicked: {
        if (Audio.sink?.audio)
            Audio.sink.audio.muted = !Audio.sink.audio.muted
    }
    onScrolled: delta => {
        if (Audio.sink?.audio) {
            const amount = Audio.sink.audio.volume + delta * 0.01
            Audio.sink.audio.volume = Math.max(0, Math.min(1.5, amount))
        }
    }

    BarRow {
        anchors.centerIn: parent
        spacing: 4

        BarText {
            text: Audio.volume + "%"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMedium
            color: Audio.muted ? Theme.textDisabled : Audio.volume > 100 ? Theme.warning : Theme.textPrimary
        }

        Text {
            text: Audio.muted ? "󰖁" : "󰕾"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            color: Audio.muted ? Theme.textDisabled : Theme.textPrimary
        }
    }
}
