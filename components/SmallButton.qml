import QtQuick
import qs.singletons

// A compact button with a label: secondary by default, filled with the accent when
// `primary`. As tall as its label needs, never less than 24 px, so a larger font in a theme
// grows it rather than spilling out.
Rectangle {
    id: root

    property string label
    property bool available: true
    property bool primary: false
    property int fontSize: Theme.fontSizeBody
    // Shown on hover when not empty
    property string tooltip: ""
    readonly property bool hovered: _area.containsMouse
    signal clicked

    implicitWidth: _label.implicitWidth + 14
    implicitHeight: Math.max(24, _label.implicitHeight + 8)
    width: implicitWidth
    height: implicitHeight
    radius: 6
    opacity: available ? 1 : 0.35
    color: primary
        ? (_area.containsMouse && available ? Theme.accentHover : Theme.accent)
        : (_area.containsMouse && available ? Theme.surfaceHover : Theme.surface)
    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

    Text {
        id: _label
        anchors.centerIn: parent
        text: root.label
        font.family: Theme.fontFamily
        font.pixelSize: root.fontSize
        color: root.primary ? Theme.onAccent : Theme.textSecondary
    }

    MouseArea {
        id: _area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.available) root.clicked()
    }

    HoverTip {
        target: root
        shown: root.tooltip !== "" && _area.containsMouse
        text: root.tooltip
    }
}
