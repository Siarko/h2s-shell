import QtQuick
import QtQuick.Layouts
import qs.api

// The fixture widget's preset settings (the bar section editor's ⚙)
ColumnLayout {
    property var module: null
    property string presetName: ""
    property string widgetType: ""

    Hint {
        text: "Good's preset " + parent.presetName
    }
}
