import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.singletons
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

    // Preset names in the shared library for this widget type
    readonly property var _knownPresets: Object.keys(JSON.parse(Config.widgetPresets || "{}")[widgetType] ?? {})

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
            color: Qt.rgba(Theme.textDim.r, Theme.textDim.g, Theme.textDim.b, 0.3)
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
        // confirm — and a field to start a new one
        RowLayout {
            width: parent.width
            spacing: 8

            Text {
                text: "Preset"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
                Layout.preferredWidth: 60
                Layout.alignment: Qt.AlignTop
                topPadding: 4
            }

            Flow {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    // ScriptModel, never the bare array — see "The Repeater crash"
                    model: ScriptModel {
                        // A just-named preset is assigned before the library has it
                        values: [""].concat(root._knownPresets,
                            root.currentPreset !== "" && !root._knownPresets.includes(root.currentPreset)
                                ? [root.currentPreset] : [])
                    }

                    Rectangle {
                        required property string modelData
                        readonly property bool picked: modelData === root.currentPreset

                        width: _presetName.implicitWidth + 16
                        height: 24
                        radius: 6
                        color: picked ? Theme.sliderAccent : (_presetArea.containsMouse ? Theme.cellHover : "transparent")
                        border.width: picked ? 0 : 1
                        border.color: Qt.rgba(Theme.textSecondary.r, Theme.textSecondary.g, Theme.textSecondary.b, 0.4)

                        Text {
                            id: _presetName
                            anchors.centerIn: parent
                            text: parent.modelData === "" ? "None" : parent.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                            color: parent.picked ? Theme.textPrimary : Theme.textSecondary
                        }

                        MouseArea {
                            id: _presetArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!parent.picked)
                                    root.presetAssigned(parent.modelData)
                            }
                        }
                    }
                }

                // A new preset: named here, created by assigning it; its settings are
                // stored as soon as one is edited below
                Rectangle {
                    width: 120
                    height: 24
                    radius: 6
                    color: Theme.cellDefault

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
                                root.presetAssigned(name)
                        }
                    }

                    Text {
                        anchors { fill: parent; leftMargin: 8 }
                        verticalAlignment: Text.AlignVCenter
                        visible: _newPreset.text === "" && !_newPreset.activeFocus
                        text: "+ New preset"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.textDim
                    }
                }
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
