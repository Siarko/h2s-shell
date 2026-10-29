import QtQuick
import qs.components
import qs.singletons

PopupWidget {
    property string profile: ""
    widgetType: "clock"

    // The format comes from the widget's preset; without one, the default
    readonly property string defaultFormat: "hh:mm:ss"
    readonly property string _format: {
        if (profile !== "") {
            var data = JSON.parse(Config.widgetProfiles || "{}");
            var fmt = data["clock"]?.[profile]?.format;
            if (fmt) return fmt;
        }
        return defaultFormat;
    }

    Text {
        text: Qt.formatDateTime(Time.date, _format)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeTitle
        color: Theme.textPrimary
        anchors.centerIn: parent
    }
}
