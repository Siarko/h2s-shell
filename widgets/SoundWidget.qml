import QtQuick
import qs.components
import qs.singletons

BarWidget {
    property var popup: null

    onHover: state => {
        if (state)
            popup.open(this, false, "sound")
    }
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

    Row {
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: Audio.volume + "%"
            font.family: Theme.fontFamily
            font.pixelSize: 14
            color: Audio.muted ? Theme.textDim : Audio.volume > 100 ? Theme.textWarning : Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: Audio.muted ? "󰖁" : "󰕾"
            font.family: Theme.fontFamily
            font.pixelSize: 18
            color: Audio.muted ? Theme.textDim : Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
