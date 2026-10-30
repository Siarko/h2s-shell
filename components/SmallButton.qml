import QtQuick
import qs.singletons

// A compact button with a label. `kind` is what it does — "normal", "save" (confirms:
// the confirm colour), "saveChange" (confirms a change to something that exists: the
// second confirm colour), "cancel", "delete" (destructive: red under the pointer, as
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

    readonly property bool _confirms: kind === "save" || kind === "saveChange"
    readonly property bool _filled: _confirms || checked
    readonly property bool _hot: _area.containsMouse && available
    // The theme's group for this kind of button: its own radius; padding and height are
    // the general button's
    readonly property var _shape: kind === "save" || kind === "saveChange" ? Theme.saveButton
        : kind === "cancel" ? Theme.cancelButton
        : kind === "delete" ? Theme.deleteButton
        : Theme.button

    implicitWidth: _label.implicitWidth + 2 * Theme.button.horizontalPadding
    implicitHeight: Math.max(Theme.button.minHeight, _label.implicitHeight + 2 * Theme.button.verticalPadding)
    width: implicitWidth
    height: implicitHeight
    radius: _shape.radius
    opacity: available ? 1 : 0.35
    color: kind === "delete" ? (_hot ? Theme.error : Theme.surface)
        : kind === "save" ? (_hot ? Theme.confirmHover : Theme.confirm)
        : kind === "saveChange" ? (_hot ? Theme.confirmSecondaryHover : Theme.confirmSecondary)
        : checked ? (_hot ? Theme.accentHover : Theme.accent)
        : (_hot ? Theme.surfaceHover : Theme.surface)
    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

    Text {
        id: _label
        anchors.centerIn: parent
        text: root.label
        font.family: Theme.fontFamily
        font.pixelSize: root.fontSize
        color: root.kind === "delete" && root._hot ? Theme.textPrimary
            : root._confirms ? Theme.textPrimary
            : root._filled ? Theme.onAccent
            : Theme.textSecondary
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
