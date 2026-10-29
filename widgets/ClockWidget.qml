import QtQuick
import qs.components
import qs.singletons

PopupWidget {
    property string preset: ""
    widgetType: "clock"

    // The format comes from the widget's preset; without one, the default
    readonly property string defaultFormat: "hh:mm:ss"
    readonly property string _format: {
        if (preset !== "") {
            var data = JSON.parse(Config.widgetPresets || "{}");
            var fmt = data["clock"]?.[preset]?.format;
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
