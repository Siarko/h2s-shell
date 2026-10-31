import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.components

// The widgets of one bar section: reorder by dragging, add, remove, and per entry its
// popup mode and widget preset. Edits come back whole through `edited`, so the owner
// stores the section as one value.
ReorderList {
    id: root

    // [{ type, preset }]
    property var entries: []
    property string section: ""
    // The shell profile being edited, picked in the settings window
    property int editIndex: -1

    signal edited(var newEntries)

    function displayName(type) {
        return WidgetRegistry.displayName(type)
    }

    items: (entries ?? []).map(entry => entry.type)
    addLabel: "＋ Add widget"
    // Once per section, except widgets that can repeat with different presets (two clocks,
    // two hardware capsules)
    addOptions: WidgetRegistry.types.filter(type => !items.includes(type) || WidgetRegistry.allowsMultiple(type))
    optionLabel: type => root.displayName(type)

    // The entries as they are, each its type and preset
    function _entries() {
        return (entries ?? []).map(entry => ({ type: entry.type, preset: entry.preset ?? "" }))
    }

    onMoved: (from, to) => {
        const list = _entries()
        list.splice(to, 0, list.splice(from, 1)[0])
        edited(list)
    }
    onRemoved: index => {
        const list = _entries()
        list.splice(index, 1)
        edited(list)
    }
    onAdded: type => edited(_entries().concat([{ type: type, preset: "" }]))

    function _setPreset(index, preset) {
        const list = _entries()
        if (list[index])
            list[index].preset = preset
        edited(list)
    }

    function _toggleExpanded(index) {
        const rows = Object.assign({}, expandedRows)
        if (rows[index])
            delete rows[index]
        else
            rows[index] = true
        expandedRows = rows
    }

    // The widget's name, and ⚙ opening its settings
    rowContent: RowLayout {
        id: _content
        property var value
        property int index
        spacing: 2

        Text {
            text: root.displayName(_content.value)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody
            color: Theme.textPrimary
            Layout.fillWidth: true
        }

        // Only for widgets with something to set: a popup mode or presets (not the settings
        // button or the tray)
        Rectangle {
            visible: WidgetRegistry.hasPopupMode(_content.value) || WidgetRegistry.hasPresets(_content.value)
            width: 24
            height: 24
            radius: Theme.iconButton.radius
            color: _gearArea.containsMouse ? Theme.surfaceHover : Theme.surfaceHoverClear
            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

            Text {
                font.family: Theme.fontFamily
                anchors.centerIn: parent
                text: "⚙"
                font.pixelSize: Theme.fontSizeBodyLarge
                color: root.expandedRows[_content.index] === true ? Theme.accent : Theme.textSecondary
            }

            MouseArea {
                id: _gearArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root._toggleExpanded(_content.index)
            }
        }
    }

    // The widget's popup mode and preset
    rowDetail: WidgetSettingsPane {
        property var value
        property int index
        widgetType: value ?? ""
        editIndex: root.editIndex
        currentPreset: root.entries[index]?.preset ?? ""
        onPresetAssigned: newName => root._setPreset(index, newName)
    }
}
