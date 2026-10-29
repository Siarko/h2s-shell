import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

// Every setting in the schema's "general" and "appearance" groups, edited in the profile
// picked in the settings window. The debug switches are always global.
ColumnLayout {
    id: root

    // The profile being edited, picked in the settings window
    property int editIndex: -1

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

    Repeater {
        // ScriptModel, never a bare array — see "The Repeater crash"
        model: ScriptModel {
            values: SettingsSchema.keysInGroup("general")
        }

        SchemaSettingEditor {
            required property string modelData
            key: modelData
            editIndex: root.editIndex
        }
    }

    // The profile's appearance choices, here until the Appearance section exists
    // (docs/plans/themes.md, stage 6)
    Text {
        text: "Appearance"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeHeading
        font.bold: true
        color: Theme.textSecondary
        Layout.topMargin: 16
        Layout.bottomMargin: 8
    }

    Repeater {
        model: ScriptModel {
            values: SettingsSchema.keysInGroup("appearance")
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
