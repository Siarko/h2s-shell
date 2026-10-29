import QtQuick

// Non-instantiated base template — concrete sources are standalone singletons.
// This file documents the common interface each source singleton must implement.
QtObject {
    property string sourceId: ""
    property string label: ""
    property string unit: "%"
    property real value: 0
    property real minValue: 0
    property real maxValue: 100
    property bool available: true
    // History.append samples, one hour
    property var history: []
    property string subtitle: ""
    property bool showProgressBar: true
}
