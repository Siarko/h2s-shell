import QtQuick
import qs.components
import qs.singletons

PopupWidget {
    property string profile: ""
    widgetType: "clock"
    popupContent: "calendar"

    readonly property string _format: {
        if (profile !== "") {
            var data = JSON.parse(Config.widgetProfiles || "{}");
            var fmt = data["clock"]?.[profile]?.format;
            if (fmt) return fmt;
        }
        return Config.datetimeFormat;
    }

    Text {
        text: Qt.formatDateTime(Time.date, _format)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeTitle
        color: Theme.textPrimary
        anchors.centerIn: parent
    }
}
