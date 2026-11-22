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
        margins: Theme.settings.pageMargin
    }
    spacing: 4

    Heading {
        text: "Media"
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
