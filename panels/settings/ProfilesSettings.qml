import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.singletons

// The profile list: what is active and why, each profile's conditions, order, enable
// switch, name, and deletion. Their values are edited on the Performance page. See
// docs/plans/adaptive-polling.md.
Flickable {
    id: root

    anchors.fill: parent
    contentHeight: _column.implicitHeight + 2 * Theme.settings.pageMargin
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    signal editValuesRequested(string profileName)

    // Name of the profile whose delete button is asking (DeleteButton), so only one asks
    property string _confirmingDelete: ""

    ColumnLayout {
        id: _column
        x: Theme.settings.pageMargin
        y: Theme.settings.pageMargin
        width: root.width - 2 * Theme.settings.pageMargin
        spacing: 6

        Text {
            text: "Profiles"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "A profile overrides settings while its conditions hold. When several apply, the one lower in the list wins. With no profiles, the built-in defaults apply. A setting pinned as global (the pin next to it) is the same in every profile."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textDisabled
        }

        // ── Active now ─────────────────────────────────────────────
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 6
            wrapMode: Text.WordWrap
            text: "Active now: " + (Profiles.activeProfiles.length > 0 ? Profiles.activeProfiles.join(", ") : "none (built-in defaults)")
                + (Object.keys(Profiles.simulated).length > 0 ? "  — simulated" : "")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBodyLarge
            color: Theme.textPrimary
        }

        Text {
            visible: Object.keys(Profiles.globals).length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Global, the same in every profile: "
                + Object.keys(Profiles.globals).map(key => SettingsSchema.entry(key)?.label ?? key).join(", ")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textSecondary
        }

        // Simulation, for trying conditions out on a machine without a battery
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: "Simulate:"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
                Layout.rightMargin: 4
            }

            Repeater {
                model: [
                    { label: "Off", facts: {} },
                    { label: "On battery", facts: { "power.onBattery": true, "battery.percent": 60 } },
                    { label: "Battery 15 %", facts: { "power.onBattery": true, "battery.percent": 15 } }
                ]

                SmallButton {
                    required property var modelData
                    label: modelData.label
                    // The simulation in force, filled with the accent
                    checked: JSON.stringify(Profiles.simulated) === JSON.stringify(modelData.facts)
                    onClicked: Profiles.simulated = modelData.facts
                }
            }

            Item { Layout.fillWidth: true }
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

        // ── The profiles ───────────────────────────────────────────
        Repeater {
            // ScriptModel, never the bare array — see "The Repeater crash"
            model: ScriptModel {
                values: Profiles.profiles
            }

            Rectangle {
                id: _card
                required property var modelData
                required property int index

                readonly property bool active: Profiles.activeProfiles.includes(modelData.name)
                readonly property var leaves: ProfileRules.flatLeaves(modelData.when)

                function setLeaves(newLeaves) {
                    Profiles.updateProfile(index, { when: newLeaves.length > 0 ? { all: newLeaves } : {} })
                }

                Layout.fillWidth: true
                Layout.topMargin: 6
                implicitHeight: _cardColumn.implicitHeight + 20
                radius: Theme.settings.cardRadius
                color: Theme.surface
                border.width: active ? Theme.border.width : 0
                border.color: Theme.accent

                ColumnLayout {
                    id: _cardColumn
                    x: 10
                    y: 10
                    width: parent.width - 20
                    spacing: 6

                    // Name, enable switch, order, delete
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        TextInput {
                            Layout.fillWidth: true
                            text: _card.modelData.name
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBodyLarge
                            font.bold: true
                            color: Theme.textPrimary
                            selectByMouse: true
                            clip: true
                            onEditingFinished: {
                                const name = text.trim();
                                if (name !== "" && name !== _card.modelData.name
                                        && !Profiles.profiles.some(profile => profile.name === name))
                                    Profiles.updateProfile(_card.index, { name: name });
                                else
                                    text = _card.modelData.name;
                            }
                        }

                        Text {
                            text: _card.active ? "active" : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.accent
                        }

                        // Enabled
                        ToggleSwitch {
                            offColor: Theme.popupBackground
                            checked: _card.modelData.enabled !== false
                            onToggled: Profiles.updateProfile(_card.index, { enabled: _card.modelData.enabled === false })
                        }

                        SmallButton {
                            label: "↑"
                            available: _card.index > 0
                            onClicked: Profiles.moveProfile(_card.index, -1)
                        }
                        SmallButton {
                            label: "↓"
                            available: _card.index < Profiles.profiles.length - 1
                            onClicked: Profiles.moveProfile(_card.index, 1)
                        }
                        DeleteButton {
                            id: _deleteProfile
                            label: "×"
                            fontSize: Theme.fontSizeBody
                            cancelTip: "Cancel — keep the profile"
                            onConfirmed: Profiles.removeProfile(_card.index)
                            // One question at a time, across the cards
                            onAskingStarted: root._confirmingDelete = _card.modelData.name
                            Connections {
                                target: root
                                function on_ConfirmingDeleteChanged() {
                                    if (root._confirmingDelete !== _card.modelData.name)
                                        _deleteProfile.asking = false;
                                }
                            }
                        }
                    }

                    // Conditions
                    Text {
                        text: "Applies when" + (_card.leaves !== null && _card.leaves.length > 0 ? " all of these hold:" : ":")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textSecondary
                    }

                    Text {
                        visible: _card.leaves === null || _card.leaves.length === 0
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        leftPadding: 8
                        text: ProfileRules.describe(_card.modelData.when)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textPrimary
                    }

                    Repeater {
                        model: ScriptModel {
                            values: _card.leaves ?? []
                        }

                        ConditionEditor {
                            required property var modelData
                            required property int index
                            Layout.leftMargin: 8
                            leaf: modelData
                            onChangedTo: newLeaf => {
                                const leaves = _card.leaves.slice();
                                leaves[index] = newLeaf;
                                _card.setLeaves(leaves);
                            }
                            onRemoved: {
                                const leaves = _card.leaves.slice();
                                leaves.splice(index, 1);
                                _card.setLeaves(leaves);
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        SmallButton {
                            visible: _card.leaves !== null
                            label: "+ condition"
                            onClicked: _card.setLeaves((_card.leaves ?? []).concat([{ fact: "power.onBattery", is: true }]))
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: Object.keys(_card.modelData.set ?? {}).length + " settings"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.textDisabled
                        }

                        SmallButton {
                            label: "Edit values"
                            onClicked: root.editValuesRequested(_card.modelData.name)
                        }
                    }
                }
            }
        }

        SmallButton {
            Layout.topMargin: 8
            label: "+ Add profile"
            onClicked: Profiles.addProfile()
        }
    }
}
