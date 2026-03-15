import QtQuick
import QtQuick.Layouts
import qs.singletons

ColumnLayout {
    anchors {
        fill: parent
        margins: 14
    }
    spacing: 4

    Text {
        text: "Media"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.bold: true
        color: Theme.textSecondary
        Layout.bottomMargin: 4
    }

    SettingOptions {
        label: "Visualizer style"
        options: ["waveform", "bars", "dots", "none"]
        labels: ["Waveform", "Bars", "Dots", "None"]
        value: Config.media.visualizerStyle
        onPicked: val => Config.media.visualizerStyle = val
    }

    SettingOptions {
        label: "Layout"
        options: ["horizontal", "vertical"]
        labels: ["Horizontal", "Vertical"]
        value: Config.media.visualizerLayout
        onPicked: val => Config.media.visualizerLayout = val
    }

    Item {
        Layout.fillHeight: true
    }
}
