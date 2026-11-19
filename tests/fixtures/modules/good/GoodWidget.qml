import QtQuick
import qs.api

// The fixture's bar widget: a cell with a popup (GoodPanel), its text from a preset
// (WidgetPresets: the manifest's presetDefaults) and a setting of the module
PopupWidget {
    id: root
    widgetType: "good"

    // Set by the bar: the module's handle, the bar entry's preset
    property var module: null
    property string preset: ""
    property var goodState: GoodState
    Component.onCompleted: {
        GoodState.widgetSawHandle = module !== null;
        GoodState.widgetSawMain = module?.main ?? null;
    }

    Text {
        anchors.centerIn: parent
        text: "GOOD " + (root.module?.value("greeting") ?? "")
        font.family: Api.theme.fontFamily
        font.pixelSize: Api.theme.fontSizeBody
        color: Api.theme.accent
    }
}
