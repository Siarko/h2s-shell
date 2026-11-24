import QtQuick
import qs.api

// The fixture's bar widget that opens ReadonlyAnimatingPanel
PopupWidget {
    widgetType: "panel-inputs.animating"
    property var module: null
    property string preset: ""
    property var inputsState: InputsState
}
