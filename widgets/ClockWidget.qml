import QtQuick
import qs.components
import qs.singletons

BarWidget {
    property var popup: null
    property string profile: ""

    readonly property string _format: {
        if (profile !== "") {
            var data = JSON.parse(Config.widgetProfiles || "{}");
            var fmt = data["clock"]?.[profile]?.format;
            if (fmt) return fmt;
        }
        return Config.datetimeFormat;
    }

    onHover: state => {
        if (state)
            popup.open(this)
    }

    Text {
        text: Qt.formatDateTime(Time.date, _format)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeTitle
        color: Theme.textPrimary
        anchors.centerIn: parent
    }
}
