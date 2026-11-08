import QtQuick
import qs.singletons

// One choice among several, outlined, filled with the accent when picked. As tall as its
// label needs, never less than `minimumHeight`.
Rectangle {
    id: root

    property string label
    property bool picked: false
    property int fontSize: Theme.fontSizeSmall
    property int minimumHeight: Theme.pill.minHeight
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
        text: root.label
        font.family: Theme.fontFamily
        font.pixelSize: root.fontSize
        color: root.picked ? Theme.onAccent : Theme.textSecondary
    }

    PointerArea {
        id: _area
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
