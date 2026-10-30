import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.panels

// The bar's widgets, edited in the profile picked in the settings window. Each section
// (left, center, right) is one setting: a profile either inherits it or has its own list
// of widgets (docs/plans/global-profiles.md). The bar's shape is in the theme:
// Appearance → Bar shape (BarShapeSettings).
Flickable {
    id: root

    // The profile being edited, picked in the settings window
    property int editIndex: -1

    anchors.fill: parent
    contentHeight: _barCol.implicitHeight
    clip: true

    ColumnLayout {
        id: _barCol
        anchors {
            fill: parent
            margins: Theme.settings.pageMargin
        }
        spacing: 4

        // The bar's size and corners are part of the theme now
        Hint {
            text: "The bar's size, margins and corners are part of the theme: Appearance → Bar shape."
        }

        Text {
            text: "Content"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.bold: true
            color: Theme.textSecondary
            Layout.topMargin: 4
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
