import QtQuick
import qs.singletons

// A compact button with a label. `kind` is what it does — "normal", "save" (confirms:
// filled with the accent), "cancel", "delete" (destructive: red under the pointer, as
// DeleteButton) — so each kind can be
// styled on its own (docs/plans/themes-stage7.md). `checked` shows a toggle that is on
// (filled with the accent), e.g. a scan running. As tall as its label needs, never less
// than 24 px, so a larger font in a theme grows it rather than spilling out.
Rectangle {
    id: root

    property string label
    property bool available: true
    property string kind: "normal"
    property bool checked: false
    property int fontSize: Theme.fontSizeBody
    // Shown on hover when not empty
    property string tooltip: ""
    readonly property bool hovered: _area.containsMouse
    signal clicked

    readonly property bool _filled: kind === "save" || checked
    readonly property bool _hot: _area.containsMouse && available

    implicitWidth: _label.implicitWidth + 14
    implicitHeight: Math.max(24, _label.implicitHeight + 8)
    width: implicitWidth
    height: implicitHeight
    radius: 6
    opacity: available ? 1 : 0.35
    color: kind === "delete" ? (_hot ? Theme.error : Theme.surface)
        : _filled ? (_hot ? Theme.accentHover : Theme.accent)
        : (_hot ? Theme.surfaceHover : Theme.surface)
    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

    Text {
        id: _label
        anchors.centerIn: parent
        text: root.label
        font.family: Theme.fontFamily
        font.pixelSize: root.fontSize
        color: root.kind === "delete" && root._hot ? Theme.textPrimary : root._filled ? Theme.onAccent : Theme.textSecondary
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
