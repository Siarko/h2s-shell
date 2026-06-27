import QtQuick
import QtQuick.Layouts
import qs.singletons
import qs.panels

Item {
    id: root
    property string profileName: ""
    property string widgetType: "hardware"

    implicitHeight: _col.implicitHeight

    readonly property var _capsuleKeys: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data[widgetType]?.[profileName]?.capsule ?? ["cpu"]
    }

    readonly property var _popupKeys: {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        return data[widgetType]?.["_popup"] ?? ["cpu", "ram", "disk", "cpuTemp", "gpu", "gpuTemp"]
    }

    function _saveCapsuleKeys(keys) {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        if (!data[widgetType])              data[widgetType] = {}
        if (!data[widgetType][profileName]) data[widgetType][profileName] = {}
        data[widgetType][profileName]["capsule"] = keys
        Config.widgetProfiles = JSON.stringify(data)
    }

    function _savePopupKeys(keys) {
        var data = JSON.parse(Config.widgetProfiles || "{}")
        if (!data[widgetType]) data[widgetType] = {}
        data[widgetType]["_popup"] = keys
        Config.widgetProfiles = JSON.stringify(data)
    }

    Column {
        id: _col
        width: parent.width
        topPadding: 4
        spacing: 12

        HardwareSourceList {
            width: parent.width
            title: "Capsule"
            model: root._capsuleKeys
            labelsKey: "_capsuleLabels"
            onListChanged: list => root._saveCapsuleKeys(list)
        }

        HardwareSourceList {
            width: parent.width
            title: "Popup"
            model: root._popupKeys
            labelsKey: "_popupLabels"
            onListChanged: list => root._savePopupKeys(list)
        }
    }
}
