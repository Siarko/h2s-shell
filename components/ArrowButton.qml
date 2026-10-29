import QtQuick
import qs.singletons

Text {
    id: root
    signal clicked

    width: 30
    height: parent.height
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeHeading
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    color: area.containsMouse ? Theme.textPrimary : Theme.textSecondary
    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing.type: Theme.easing("hover") } }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
