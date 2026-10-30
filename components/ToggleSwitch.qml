import QtQuick
import qs.singletons

// An on/off switch: a track filled with the accent when on, and a knob sliding to that
// side. Reports a click with `toggled`; the owner changes `checked` (it follows the value
// it shows, which may change elsewhere). Small by default, as in the settings; popups use
// a larger one (width 44, height 24, with offColor Theme.textDisabled).
Rectangle {
    id: root

    property bool checked: false
    property color offColor: Theme.surface
    signal toggled

    implicitWidth: 36
    implicitHeight: 20
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: checked ? Theme.accent : offColor
    Behavior on color { ColorAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }

    Rectangle {
        x: root.checked ? root.width - width - 2 : 2
        anchors.verticalCenter: parent.verticalCenter
        width: root.height - 4
        height: width
        radius: width / 2
        color: Theme.textPrimary
        Behavior on x { NumberAnimation { duration: Theme.duration("state"); easing: Theme.curve("state") } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
