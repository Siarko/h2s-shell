import QtQuick
import qs.singletons

// One choice among several, outlined, filled with the accent when picked. As tall as its
// label needs, never less than `minimumHeight`.
Rectangle {
    id: root

    property string label
    property bool picked: false
    property int fontSize: Theme.fontSizeSmall
    property int minimumHeight: 22
    signal clicked

    implicitWidth: _label.implicitWidth + 14
    implicitHeight: Math.max(minimumHeight, _label.implicitHeight + 6)
    width: implicitWidth
    height: implicitHeight
    radius: 6
    color: picked ? Theme.accent : (_area.containsMouse ? Theme.surfaceHover : Theme.surfaceHoverClear)
    border.width: picked ? 0 : 1
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

    MouseArea {
        id: _area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
