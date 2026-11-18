import QtQuick
import qs.singletons

// One choice among several, outlined, filled with the accent when picked. `size` is "s",
// "m" or "l": the theme's three pill heights (ThemeRules.pillHeight). As tall as its
// label needs, never less than its size's height. The label is one line, cut at the
// right when the pill is narrower than it.
Rectangle {
    id: root

    property string label
    property bool picked: false
    property int fontSize: Theme.fontSizeSmall
    property string size: "s"
    // The size's height. The shell's views set `size`, never this.
    property int minimumHeight: ThemeRules.pillHeight(Theme.pill, size)
    // What the choice means, shown on hover ("" none)
    property string tooltip: ""
    signal clicked

    implicitWidth: _label.implicitWidth + 2 * Theme.pill.horizontalPadding
    implicitHeight: Math.max(minimumHeight, _label.implicitHeight + 6)
    width: implicitWidth
    height: implicitHeight
    radius: Theme.pill.radius
    color: picked ? Theme.accent : (_area.lit ? Theme.surfaceHover : Theme.surfaceHoverClear)
    border.width: picked ? 0 : Theme.border.width
    border.color: Theme.outline
    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

    Text {
        id: _label
        anchors.centerIn: parent
        width: Math.min(implicitWidth, Math.max(0, root.width - 2 * Theme.pill.horizontalPadding))
        text: root.label
        textFormat: Text.PlainText
        maximumLineCount: 1
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: root.fontSize
        color: root.picked ? Theme.onAccent : Theme.textSecondary
    }

    PointerArea {
        id: _area
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    HoverTip {
        target: root
        shown: root.tooltip !== "" && _area.containsMouse
        text: root.tooltip
    }
}
