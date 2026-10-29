import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons

// The profile list: what is active and why, each profile's conditions, order, enable
// switch, name, and deletion. Their values are edited on the Performance page. See
// docs/plans/adaptive-polling.md.
Flickable {
    id: root

    anchors.fill: parent
    contentHeight: _column.implicitHeight + 28
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    signal editValuesRequested(string profileName)

    // Name of the profile whose delete button was clicked once; a second click deletes
    property string _confirmingDelete: ""

    component SmallButton: Rectangle {
        property string label
        property bool available: true
        signal clicked

        width: _label.implicitWidth + 14
        height: 24
        radius: 6
        opacity: available ? 1 : 0.35
        color: _area.containsMouse && available ? Theme.cellHover : Theme.cellDefault

        Text {
            id: _label
            anchors.centerIn: parent
            text: parent.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textSecondary
        }

        MouseArea {
            id: _area
            anchors.fill: parent
            hoverEnabled: true
            enabled: parent.available
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    ColumnLayout {
        id: _column
        x: 14
        y: 14
        width: root.width - 28
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
            color: Theme.textDim
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
                    color: JSON.stringify(Profiles.simulated) === JSON.stringify(modelData.facts)
                        ? Theme.sliderAccent : Theme.cellDefault
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
            color: Theme.textError
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
                radius: 8
                color: Theme.cellDefault
                border.width: active ? 1 : 0
                border.color: Theme.sliderAccent

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
                            color: Theme.sliderAccent
                        }

                        // Enabled
                        Rectangle {
                            width: 36
                            height: 20
                            radius: 10
                            color: _card.modelData.enabled !== false ? Theme.sliderAccent : Theme.popupBackground

                            Rectangle {
                                x: _card.modelData.enabled !== false ? parent.width - width - 2 : 2
                                y: 2
                                width: 16
                                height: 16
                                radius: 8
                                color: Theme.textPrimary
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Profiles.updateProfile(_card.index, { enabled: _card.modelData.enabled === false })
                            }
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
                        SmallButton {
                            label: root._confirmingDelete === _card.modelData.name ? "Delete?" : "×"
                            onClicked: {
                                if (root._confirmingDelete === _card.modelData.name) {
                                    root._confirmingDelete = "";
                                    Profiles.removeProfile(_card.index);
                                } else {
                                    root._confirmingDelete = _card.modelData.name;
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
                            color: Theme.textDim
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
