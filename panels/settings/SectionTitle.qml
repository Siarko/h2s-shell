import QtQuick
import QtQuick.Layouts
import qs.singletons

// A section's title within a settings page (System → Network's pages): smaller than the
// page's Heading, bold. Its children, written inside it, are controls at the right end of
// its line (a switch for the section, its buttons): the title then fills the width a
// layout gives it, and its line is as tall as the controls need.
//
//   SectionTitle { text: "Taildrop"; ToggleSwitch { … } }
Text {
    id: root

    default property alias controls: _controls.data

    readonly property bool _hasControls: _controls.children.length > 0
    readonly property real _controlsSpace: Math.max(0, _controls.implicitHeight - contentHeight) / 2

    Layout.topMargin: 16
    Layout.bottomMargin: 6
    Layout.fillWidth: _hasControls
    rightPadding: _hasControls ? _controls.implicitWidth + 8 : 0
    topPadding: _hasControls ? _controlsSpace : 0
    bottomPadding: _hasControls ? _controlsSpace : 0
    textFormat: Text.PlainText
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeBody
    font.bold: true
    color: Theme.textPrimary

    RowLayout {
        id: _controls
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        visible: root._hasControls
        spacing: 8
    }
}
