import QtQuick
import qs.components
import qs.singletons

BarWidget {
    property var popup: null
    property string profile: ""
    property string widgetType: "clock"

    readonly property string _popupMode: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data["clock"]?.["_popupMode"] ?? "hover"
    }

    readonly property string _format: {
        if (profile !== "") {
            var data = JSON.parse(Config.widgetProfiles || "{}");
            var fmt = data["clock"]?.[profile]?.format;
            if (fmt) return fmt;
        }
        return Config.datetimeFormat;
    }

    onClicked: {
        if (_popupMode !== "click") return
        if (popup?.active && popup?.contentType === "calendar") popup.close()
        else popup.open(this, true, "calendar")
    }
    onHover: state => {
        if (_popupMode !== "hover") return
        if (state) popup.open(this, false, "calendar")
    }

    Text {
        text: Qt.formatDateTime(Time.date, _format)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeTitle
        color: Theme.textPrimary
        anchors.centerIn: parent
    }
}
