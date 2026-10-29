import QtQuick
import QtQuick.Layouts
import qs.singletons

ColumnLayout {
    id: root

    // The profile being edited, picked in the settings window
    property int editIndex: -1

    anchors {
        fill: parent
        margins: 14
    }
    spacing: 4

    Text {
        text: "Media"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeHeading
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

    // Per profile (docs/plans/global-profiles.md); the settings above are not yet
    SchemaSettingEditor {
        visible: root.editIndex >= 0
        key: "polling.visualizer.fps"
        editIndex: root.editIndex
    }

    Item {
        Layout.fillHeight: true
    }
}
