import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.panels
import qs.panels.settings

// Settings of a hardware widget. The capsule on the bar — its sources and their labels —
// belongs to the widget's preset; the popup is a setting of the shell profile being
// edited (docs/plans/global-profiles.md).
Item {
    id: root
    property string presetName: ""
    property string widgetType: "hardware"
    // The shell profile being edited, picked in the settings window
    property int editIndex: -1

    implicitHeight: _col.implicitHeight

    readonly property var _preset: JSON.parse(Config.widgetPresets || "{}")[widgetType]?.[presetName] ?? {}

    function _savePreset(changes) {
        var data = JSON.parse(Config.widgetPresets || "{}")
        if (!data[widgetType])             data[widgetType] = {}
        if (!data[widgetType][presetName]) data[widgetType][presetName] = {}
        Object.assign(data[widgetType][presetName], changes)
        Config.widgetPresets = JSON.stringify(data)
    }

    Column {
        id: _col
        width: parent.width
        topPadding: 4
        spacing: 12

        HardwareSourceList {
            width: parent.width
            title: "Capsule"
            model: root._preset.capsule ?? ["cpu"]
            labels: root._preset.capsuleLabels ?? {}
            onListChanged: list => root._savePreset({ capsule: list })
            onLabelsEdited: labels => root._savePreset({ capsuleLabels: labels })
        }

        // Status, pin and reset for the popup setting; the list below edits its value
        SchemaSettingEditor {
            id: _popupSetting
            width: parent.width
            key: "widgets.hardware.popup"
            editIndex: root.editIndex
        }

        HardwareSourceList {
            width: parent.width
            title: "Popup"
            opacity: _popupSetting.inherits && !_popupSetting.global ? 0.6 : 1
            model: _popupSetting.shownValue?.sources ?? Hardware.sourceIds
            labels: _popupSetting.shownValue?.labels ?? {}
            onListChanged: list => _popupSetting.edited({ sources: list, labels: _popupSetting.shownValue?.labels ?? {} })
            onLabelsEdited: labels => _popupSetting.edited({ sources: _popupSetting.shownValue?.sources ?? null, labels: labels })
        }
    }
}
