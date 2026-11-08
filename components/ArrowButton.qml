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
    color: area.lit ? Theme.textPrimary : Theme.textSecondary
    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

    PointerArea {
        id: area
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
