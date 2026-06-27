import QtQuick
import qs.components
import qs.singletons

BarWidget {
    property var popup: null
    property string widgetType: "sound"

    readonly property string _popupMode: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data["sound"]?.["_popupMode"] ?? "hover"
    }

    onClicked: {
        if (_popupMode !== "click") return
        if (popup?.active && popup?.contentType === "sound") popup.close()
        else popup.open(this, true, "sound")
    }
    onHover: state => {
        if (_popupMode !== "hover") return
        if (state) popup.open(this, false, "sound")
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
            font.pixelSize: Theme.fontSizeMedium
            color: Audio.muted ? Theme.textDim : Audio.volume > 100 ? Theme.textWarning : Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: Audio.muted ? "󰖁" : "󰕾"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            color: Audio.muted ? Theme.textDim : Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
