import QtQuick

Text {
    id: root
    signal clicked

    width: 30
    height: parent.height
    font.pixelSize: 18
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    color: area.containsMouse ? Theme.textPrimary : Theme.textSecondary

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
