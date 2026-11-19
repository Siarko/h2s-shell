import QtQuick
import qs.api

// The fixture's bar widget: a cell that opens ReadonlyOpenerPanel
PopupWidget {
    widgetType: "panel-opener"
    property var module: null
    property string preset: ""
    property var openerState: OpenerState
}
