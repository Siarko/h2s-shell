import QtQuick
import QtQuick.Layouts
import qs.singletons

ColumnLayout {
    anchors {
        fill: parent
        margins: 14
    }
    spacing: 0

    Text {
        text: "General"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeHeading
        font.bold: true
        color: Theme.textSecondary
        Layout.bottomMargin: 8
    }

    SettingBool {
        label: "Debug Mode"
        value: Config.general.debug ?? false
        onValueChanged: Config.general.debug = value
    }
    SettingBool {
        label: "Debug Mode | Fetch"
        value: Config.general.fetch_debug ?? false
        onValueChanged: Config.general.fetch_debug = value
    }

    Item {
        Layout.fillHeight: true
    }
}
