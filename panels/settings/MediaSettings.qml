import QtQuick
import QtQuick.Layouts
import Quickshell
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

    Repeater {
        // ScriptModel, never a bare array — see "The Repeater crash"
        model: ScriptModel {
            values: SettingsSchema.keysInGroup("media")
        }

        SchemaSettingEditor {
            required property string modelData
            key: modelData
            editIndex: root.editIndex
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
