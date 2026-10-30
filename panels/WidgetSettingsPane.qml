import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons
import qs.components
import qs.panels.settings

Item {
    id: root

    property string widgetType: ""
    // The widget preset this bar entry uses, "" for none
    property string currentPreset: ""
    // The shell profile being edited, picked in the settings window
    property int editIndex: -1

    signal presetAssigned(string newPresetName)

    implicitHeight: _col.implicitHeight + 12

    readonly property bool _hasPresets: WidgetRegistry.hasPresets(widgetType)
    // Preset names in the shared library for this widget type
    readonly property var _knownPresets: WidgetPresets.names(widgetType)
    // Where the current preset is used, across every shell profile
    readonly property var _usages: currentPreset !== "" ? WidgetPresets.usages(widgetType, currentPreset) : []
    property bool _renaming: false
    onCurrentPresetChanged: {
        _renaming = false
        _deletePreset.asking = false
    }

    // Creates the preset if it is new, then assigns it to this bar entry
    function _assignNew(name) {
        WidgetPresets.create(widgetType, name)
        presetAssigned(name)
    }

    readonly property bool _hasPopup: WidgetRegistry.hasPopupMode(widgetType)


    Column {
        id: _col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: 6
            leftMargin: 8
            rightMargin: 8
        }
        spacing: 4

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.divider
        }

        // Popup mode is a setting of the shell profile being edited
        SchemaSettingEditor {
            visible: root._hasPopup
            width: parent.width
            key: "widgets." + root.widgetType + ".popupMode"
            editIndex: root.editIndex
            label: "Popup"
        }

        // The preset: a pill per preset in the library, picked at once — no field to
        // confirm — and a field to start a new one. Only for widgets that have presets.
        RowLayout {
            visible: root._hasPresets
            width: parent.width
            spacing: 8

            Text {
                text: "Preset"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
                Layout.preferredWidth: 60
                // A label longer than the column (a larger font) is cut, not run into the field
                elide: Text.ElideRight
                Layout.alignment: Qt.AlignTop
                topPadding: 4
            }

            Flow {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    // ScriptModel, never the bare array — see "The Repeater crash"
                    model: ScriptModel {
                        values: [""].concat(root._knownPresets)
                    }

                    Pill {
                        required property string modelData
                        label: modelData === "" ? "None" : modelData
                        picked: modelData === root.currentPreset
                        fontSize: Theme.fontSizeBody
                        minimumHeight: 24
                        onClicked: {
                            if (!picked)
                                root.presetAssigned(modelData)
                        }
                    }
                }

                // A new preset, stored as soon as it is named
                Rectangle {
                    width: 120
                    height: 24
                    radius: 6
                    color: Theme.surface

                    TextInput {
                        id: _newPreset
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textPrimary
                        verticalAlignment: TextInput.AlignVCenter
                        selectByMouse: true
                        clip: true
                        onAccepted: {
                            const name = text.trim()
                            text = ""
                            focus = false
                            if (name !== "" && name !== root.currentPreset)
                                root._assignNew(name)
                        }
                    }

                    Text {
                        anchors { fill: parent; leftMargin: 8 }
                        verticalAlignment: Text.AlignVCenter
                        visible: _newPreset.text === "" && !_newPreset.activeFocus
                        text: "+ New preset"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textDisabled
                    }
                }
            }
        }

        // Without a preset the widget shows its defaults; one click gives it a preset of
        // its own to edit
        Text {
            visible: root._hasPresets && root.currentPreset === ""
            width: parent.width
            leftPadding: 68
            text: "Shows the defaults. <a href=\"customize\">Customize</a> to give it its own preset."
            textFormat: Text.StyledText
            linkColor: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.textDisabled
            onLinkActivated: root._assignNew(WidgetPresets.freeName(root.widgetType))

            HoverHandler { cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }

        // The current preset: where it is used — an edit changes all of them
        Text {
            visible: root._hasPresets && root.currentPreset !== "" && !root._renaming
            width: parent.width
            leftPadding: 68
            wrapMode: Text.WordWrap
            text: root._usages.length > 1
                ? "Shared — used in " + root._usages.map(usage => usage.profile + " · " + usage.section).join(", ")
                : root._usages.length === 1
                    ? "Used in " + root._usages[0].profile + " · " + root._usages[0].section
                    : "Not used on any bar yet"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: root._usages.length > 1 ? Theme.accent : Theme.textDisabled
        }

        // Rename / delete, on a row of their own so a wider label never runs off the edge
        RowLayout {
            visible: root._hasPresets && root.currentPreset !== ""
            width: parent.width
            spacing: 6

            Item { Layout.preferredWidth: 60 }

            Rectangle {
                visible: root._renaming
                Layout.fillWidth: true
                height: 24
                radius: 6
                color: Theme.surface
                border.width: _renameInput.taken ? 1 : 0
                border.color: Theme.error

                TextInput {
                    id: _renameInput
                    // Another preset of this type already has the name
                    readonly property bool taken: text.trim() !== root.currentPreset
                        && root._knownPresets.includes(text.trim())
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: taken ? Theme.error : Theme.textPrimary
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    clip: true
                    onAccepted: {
                        const name = text.trim()
                        if (name === root.currentPreset || name === "") {
                            root._renaming = false
                        } else if (!taken && WidgetPresets.rename(root.widgetType, root.currentPreset, name)) {
                            root._renaming = false
                        }
                    }
                    Keys.onEscapePressed: root._renaming = false
                }
            }

            SmallButton {
                label: root._renaming ? "Cancel" : "Rename"
                kind: root._renaming ? "cancel" : "normal"
                fontSize: Theme.fontSizeSmall
                onClicked: {
                    root._renaming = !root._renaming
                    _deletePreset.asking = false
                    if (root._renaming) {
                        _renameInput.text = root.currentPreset
                        _renameInput.forceActiveFocus()
                        _renameInput.selectAll()
                    }
                }
            }

            DeleteButton {
                id: _deletePreset
                confirmLabel: "Delete everywhere?"
                cancelTip: "Cancel — keep the preset"
                onAskingStarted: root._renaming = false
                onConfirmed: WidgetPresets.remove(root.widgetType, root.currentPreset)
            }

            // Takes the spare width, so the buttons stay packed at the left instead of the
            // layout spreading them out (the rename field takes it while renaming)
            Item {
                visible: !root._renaming
                Layout.fillWidth: true
            }
        }

        Loader {
            id: _specificLoader
            width: parent.width
            height: item ? item.implicitHeight : 0
            visible: root.currentPreset !== ""
            source: visible ? WidgetRegistry.settingsUrl(root.widgetType) : ""
            onLoaded: {
                item.presetName = Qt.binding(() => root.currentPreset)
                if (item.editIndex !== undefined)
                    item.editIndex = Qt.binding(() => root.editIndex)
                item.widgetType  = Qt.binding(() => root.widgetType)
            }
        }
    }
}
