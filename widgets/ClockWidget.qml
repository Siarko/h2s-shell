import QtQuick
import qs.components
import qs.singletons

PopupWidget {
    property string preset: ""
    widgetType: "clock"

    // From the widget's preset; without one, the clock default
    readonly property string _format: WidgetPresets.value("clock", preset, "format") || WidgetPresets.defaults.clock.format

    BarText {
        text: Qt.formatDateTime(Time.date, _format)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeTitle
        color: Theme.textPrimary
        anchors.centerIn: parent
    }
}
