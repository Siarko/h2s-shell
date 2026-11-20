import QtQuick
import QtQuick.Layouts
import qs.singletons

// A section heading on a settings page. Its children, written inside it, are controls at
// the right end of its line (a switch for the page, its buttons): the heading then fills
// the width a layout gives it, and its line is as tall as the controls need.
//
//   Heading { text: "Wi-Fi"; ToggleSwitch { … } }
Text {
    id: root

    default property alias controls: _controls.data

    readonly property bool _hasControls: _controls.children.length > 0
    readonly property real _controlsSpace: Math.max(0, _controls.implicitHeight - contentHeight) / 2

    Layout.fillWidth: _hasControls
    rightPadding: _hasControls ? _controls.implicitWidth + 8 : 0
    topPadding: _hasControls ? _controlsSpace : 0
    bottomPadding: _hasControls ? _controlsSpace : 0
    textFormat: Text.PlainText
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeHeading
    font.bold: true
    color: Theme.textSecondary

    RowLayout {
        id: _controls
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        visible: root._hasControls
        spacing: 8
    }
}
