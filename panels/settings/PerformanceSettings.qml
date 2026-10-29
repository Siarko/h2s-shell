import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

// Polling rates, graph and power settings, edited in one profile at a time. Which
// profile is picked at the top; values that profile does not set are shown as inherited
// from the profiles above it, and a value a later active profile overrides right now is
// marked. See docs/plans/adaptive-polling.md.
Flickable {
    id: root

    anchors.fill: parent
    contentHeight: _column.implicitHeight + 28
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // The edited profile, by name so it survives reordering; Full, else the first
    property string editedName: ""
    readonly property int editIndex: {
        const byName = Profiles.profiles.findIndex(profile => profile.name === editedName);
        if (byName >= 0)
            return byName;
        const full = Profiles.profiles.findIndex(profile => profile.name === "Full");
        return full >= 0 ? full : (Profiles.profiles.length > 0 ? 0 : -1);
    }
    readonly property var edited: editIndex >= 0 ? Profiles.profiles[editIndex] : null

    readonly property var _sections: [
        { title: "Polling and graphs", keys: SettingsSchema.keysInGroup("performance") },
        { title: "Power", keys: SettingsSchema.keysInGroup("power") }
    ]

    // The later active profile overriding a key right now, if any
    function _overriddenBy(key) {
        const setter = Profiles.setBy(key);
        const setterIndex = Profiles.profiles.findIndex(profile => profile.name === setter);
        return setterIndex > editIndex ? setter : "";
    }

    ColumnLayout {
        id: _column
        x: 14
        y: 14
        width: root.width - 28
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

        SettingOptions {
            visible: root.edited !== null
            label: "Editing profile"
            options: Profiles.profiles.map(profile => profile.name)
            labels: Profiles.profiles.map(profile =>
                profile.name + (Profiles.activeProfiles.includes(profile.name) ? " •" : ""))
            value: root.edited?.name ?? ""
            onPicked: name => root.editedName = name
        }

        Text {
            visible: root.edited !== null
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: (Profiles.activeProfiles.includes(root.edited?.name) ? "Active now. " : "Not active now. ")
                + "Applies when: " + ProfileRules.describe(root.edited?.when) + ". • marks active profiles."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textDim
            Layout.bottomMargin: 6
        }

        Text {
            visible: Profiles.lastError !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Profiles.lastError
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textError
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
                        ownValue: root.edited?.set?.[modelData]
                        inheritedValue: Profiles.inheritedValue(root.editIndex, modelData)
                        overriddenBy: root._overriddenBy(modelData)
                        onEdited: newValue => Profiles.setOverride(root.editIndex, modelData, newValue)
                        onReset: Profiles.clearOverride(root.editIndex, modelData)
                    }
                }
            }
        }
    }
}
