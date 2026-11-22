import QtQuick
import QtQuick.Layouts
import qs.singletons

// A section's title within a settings page: smaller than the page's Heading, a step larger
// than the rows' labels, bold, with a line above it that stands the section apart from what
// comes before (`divider`; off for the first section under a page's heading) — the same look
// as SettingsSection's title. Its children, written inside it, are controls at the right end
// of its line (a switch for the section, its buttons): the title then fills the width a
// layout gives it, and its line is as tall as the controls need.
//
//   SectionTitle { text: "Taildrop"; ToggleSwitch { … } }
Text {
    id: root

    default property alias controls: _controls.data
    // The line above the title
    property bool divider: true

    readonly property bool _hasControls: _controls.children.length > 0
    readonly property real _controlsSpace: Math.max(0, _controls.implicitHeight - contentHeight) / 2
    // The line and the room under it, inside the top margin
    readonly property real _lineRoom: divider ? Theme.border.width + Theme.settings.sectionLineGap : 0

    Layout.topMargin: divider ? Theme.settings.sectionGap + _lineRoom : Theme.settings.sectionLineGap
    Layout.bottomMargin: Theme.settings.sectionTitleGap
    Layout.fillWidth: _hasControls
    rightPadding: _hasControls ? _controls.implicitWidth + 8 : 0
    topPadding: _hasControls ? _controlsSpace : 0
    bottomPadding: _hasControls ? _controlsSpace : 0
    textFormat: Text.PlainText
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeMedium
    font.bold: true
    color: Theme.textPrimary

    // Drawn in the top margin, across the whole column the title stands in (a title without
    // controls is only as wide as its text)
    Rectangle {
        objectName: "sectionDivider"
        visible: root.divider
        x: -root.x
        y: -root._lineRoom
        width: root.parent ? root.parent.width : root.width
        height: Theme.border.width
        color: Theme.divider
    }

    RowLayout {
        id: _controls
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        visible: root._hasControls
        spacing: 8
    }
}
