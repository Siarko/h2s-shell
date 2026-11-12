import QtQuick
import qs.singletons

// A place a wallpaper is chosen for — a monitor, a workspace, a day — with the chosen
// image's thumbnail (Wallpaper settings). Picked, the thumbnails below assign to it; the
// × clears its choice.
Rectangle {
    id: root

    property string label: ""
    // The chosen image, absolute; "" for none
    property string image: ""
    // What an unchosen one shows instead, e.g. "first chosen"
    property string emptyText: "—"
    property bool picked: false
    signal clicked()
    signal cleared()

    implicitWidth: 76
    implicitHeight: _column.implicitHeight + 8
    radius: Theme.field.radius
    color: picked ? Theme.accentTint : (_area.lit ? Theme.fillSubtle : "transparent")
    border.width: picked ? Theme.border.selectedWidth : Theme.border.width
    border.color: picked ? Theme.accent : Theme.outline
    Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }

    Column {
        id: _column
        x: 4
        y: 4
        width: parent.width - 8
        spacing: 3

        Rectangle {
            width: parent.width
            height: Math.round(width * 0.6)
            radius: Theme.field.radius
            color: Theme.fillSubtle
            clip: true

            Image {
                anchors.fill: parent
                visible: root.image !== ""
                source: root.image === "" ? "" : "file://" + root.image.split("/").map(encodeURIComponent).join("/")
                sourceSize: Qt.size(width * 2, height * 2)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 4
                visible: root.image === ""
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.emptyText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: root.picked ? Theme.textPrimary : Theme.textSecondary
        }
    }

    PointerArea {
        id: _area
        centred: false
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    // Clears the choice; above the slot's own area
    Rectangle {
        visible: root.image !== ""
        anchors { right: parent.right; top: parent.top; margins: 1 }
        width: 18
        height: 18
        radius: 9
        color: _clearArea.lit ? Theme.error : Theme.surface
        border.width: Theme.border.width
        border.color: Theme.outline

        Text {
            anchors.centerIn: parent
            text: "×"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: _clearArea.lit ? Theme.onAccent : Theme.textSecondary
        }

        PointerArea {
            id: _clearArea
            cursorShape: Qt.PointingHandCursor
            onClicked: root.cleared()
        }

        HoverTip {
            target: parent
            shown: _clearArea.containsMouse
            text: "Clear the choice"
        }
    }
}
