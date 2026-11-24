import QtQuick
import qs.api

// The fixture's bar widget that opens ReadonlyHeightPanel
PopupWidget {
    widgetType: "panel-inputs.height"
    property var module: null
    property string preset: ""
    property var inputsState: InputsState
}
