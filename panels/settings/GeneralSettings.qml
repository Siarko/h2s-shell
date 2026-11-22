import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons
import qs.components

// Every setting in the schema's "general" and "appearance" groups, edited in the profile
// picked in the settings window. The debug switches are always global. A settings page
// block, the place settings.general: modules' elements come at its end, given the profile
// being edited as `editIndex` (ModuleRules.anchorTable).
SettingsPage {
    id: root

    // The profile being edited, picked in the settings window
    property int editIndex: -1

    anchors.fill: parent
    title: "General"
    context: ({ editIndex: root.editIndex })

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

    // The profile's look: which theme it uses, and how much things move. Behaviour, so per
    // profile; the theme itself is edited in the Appearance tab
    Text {
        text: "Theme and motion"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeHeading
        font.bold: true
        color: Theme.textSecondary
        Layout.topMargin: 16
        Layout.bottomMargin: 2
    }

    Hint {
        text: "Which theme this profile uses, and how fast things move in it. The theme itself — colours, fonts, the bar's "
            + "shape, animations — is edited in the Appearance tab."
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
}
