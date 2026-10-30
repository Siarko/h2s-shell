import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

// Polling rates, graph and power settings, edited in the profile picked in the settings
// window; values that profile does not set are shown as inherited from the profiles
// above it, and a value a later active profile overrides right now is marked. See
// docs/plans/adaptive-polling.md.
Flickable {
    id: root

    anchors.fill: parent
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // The profile being edited, picked in the settings window
    property int editIndex: -1
    readonly property var edited: editIndex >= 0 ? Profiles.profiles[editIndex] : null

    readonly property var _sections: [
        { title: "Polling and graphs", keys: SettingsSchema.keysInGroup("performance") },
        { title: "Power", keys: SettingsSchema.keysInGroup("power") }
    ]

    ColumnLayout {
        id: _column
        x: Theme.settings.pageMargin
        y: Theme.settings.pageMargin
        width: root.width - 2 * Theme.settings.pageMargin
        spacing: 4

        Text {
            text: "Performance"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.bottomMargin: 4
        }

        Text {
            visible: root.edited === null
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "There are no profiles, so the built-in defaults apply. Add a profile on the Profiles page to change them."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textSecondary
        }

        Text {
            visible: Profiles.lastError !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Profiles.lastError
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.error
        }

        Repeater {
            // ScriptModel, never a bare array — see "The Repeater crash"
            model: ScriptModel {
                values: root.edited !== null ? root._sections : []
            }

            ColumnLayout {
                id: _section
                required property var modelData
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: _section.modelData.title
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    font.bold: true
                    color: Theme.textSecondary
                    Layout.topMargin: 10
                    Layout.bottomMargin: 2
                }

                Repeater {
                    model: ScriptModel {
                        values: _section.modelData.keys
                    }

                    SchemaSettingEditor {
                        required property string modelData
                        key: modelData
                        editIndex: root.editIndex
                    }
                }
            }
        }
    }
}
