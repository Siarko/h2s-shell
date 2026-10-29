import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.panels

// The bar's geometry, corners and widgets, edited in the profile picked in the settings
// window. Each section (left, center, right) is one setting: a profile either inherits
// it or has its own list of widgets (docs/plans/global-profiles.md).
Flickable {
    id: root

    // The profile being edited, picked in the settings window
    property int editIndex: -1

    function _value(name) {
        return Profiles.editedValue(editIndex, "bar.layout." + name)
    }

    function _write(name, value) {
        Profiles.writeSetting(editIndex, "bar.layout." + name, value)
    }

    // The top offset has to fit between the bar and the edge of its reserved space
    function _clampTopOffset(reservedSpace, barHeight) {
        if (_value("topOffset") > reservedSpace - barHeight)
            _write("topOffset", reservedSpace - barHeight)
    }

    anchors.fill: parent
    contentHeight: _barCol.implicitHeight
    clip: true

    ColumnLayout {
        id: _barCol
        anchors {
            fill: parent
            margins: 14
        }
        spacing: 4

        Text {
            text: "Geometry"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
        }

        SchemaSettingEditor {
            key: "bar.layout.barHeight"
            editIndex: root.editIndex
            editHook: newValue => {
                root._write("barHeight", newValue)
                if (root._value("reservedSpace") < newValue)
                    root._write("reservedSpace", newValue)
                root._clampTopOffset(Math.max(root._value("reservedSpace"), newValue), newValue)
            }
        }

        SchemaSettingEditor {
            key: "bar.layout.reservedSpace"
            editIndex: root.editIndex
            editHook: newValue => {
                const value = Math.max(newValue, root._value("barHeight"))
                root._write("reservedSpace", value)
                root._clampTopOffset(value, root._value("barHeight"))
            }
        }

        SchemaSettingEditor {
            key: "bar.layout.topOffset"
            editIndex: root.editIndex
            maximum: Math.max(0, root._value("reservedSpace") - root._value("barHeight"))
            available: root._value("reservedSpace") > root._value("barHeight")
        }

        Repeater {
            model: ["leftMargin", "rightMargin", "leftPadding", "rightPadding"]

            SchemaSettingEditor {
                required property string modelData
                key: "bar.layout." + modelData
                editIndex: root.editIndex
            }
        }

        Text {
            text: "Corners"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.topMargin: 12
        }

        Repeater {
            model: ["radiusTopLeft", "radiusTopRight", "radiusBottomLeft", "radiusBottomRight"]

            SchemaSettingEditor {
                required property string modelData
                key: "bar.layout." + modelData
                editIndex: root.editIndex
            }
        }

        Text {
            text: "Content"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.topMargin: 12
        }

        // One section: its status, pin and reset come from the schema editor; the list
        // below edits its value, and editing an inherited section copies it in
        Repeater {
            model: ["left", "center", "right"]

            ColumnLayout {
                id: _section
                required property string modelData
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 2

                SchemaSettingEditor {
                    id: _sectionSetting
                    key: "bar." + _section.modelData
                    editIndex: root.editIndex
                }

                BarSectionList {
                    section: _section.modelData
                    editIndex: root.editIndex
                    opacity: _sectionSetting.inherits && !_sectionSetting.global ? 0.6 : 1
                    entries: _sectionSetting.shownValue ?? []
                    onEdited: newEntries => _sectionSetting.edited(newEntries)
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
