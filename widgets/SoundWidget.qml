import QtQuick
import qs.components
import qs.singletons

PopupWidget {
    widgetType: "sound"

    // What its actions act on (a stand-in in tests): the default output's audio
    property var actionTarget: Audio

    function runAction(id, details) {
        const audio = actionTarget.sink?.audio;
        if (!audio)
            return;
        if (id === "mute")
            audio.muted = !audio.muted;
        else if (id === "volume")
            audio.volume = CoreActionRules.volumeAfter(audio.volume, details.amount);
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
