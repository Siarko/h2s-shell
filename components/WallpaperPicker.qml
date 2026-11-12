import QtQuick
import QtQuick.Layouts
import qs.singletons

// The folder's thumbnails opened for one purpose (Wallpaper settings): choosing the image
// of a place — a click picks it, and the owner closes the picker — or ticking the images
// to draw from (`multiple`) until Done. The header says which, so a click never does
// something unseen.
ColumnLayout {
    id: root

    // "Choosing for Workspace 3", "Tick the images to draw from"
    property string title: ""
    property bool multiple: false
    property string folder: ""
    property var files: []
    property var marked: []
    property var badges: ({})
    // A second button beside Done ("Clear", "Use all"); "" for none
    property string extraLabel: ""
    property bool extraAvailable: true
    signal picked(string path)
    signal done()
    signal extra()

    spacing: 6

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: _header.implicitHeight + 12
        radius: Theme.field.radius
        color: Theme.accentTint
        border.width: Theme.border.width
        border.color: Theme.accent

        RowLayout {
            id: _header
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 6 }
            spacing: 6

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.title
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textPrimary
            }
            SmallButton {
                visible: root.extraLabel !== ""
                label: root.extraLabel
                available: root.extraAvailable
                onClicked: root.extra()
            }
            SmallButton {
                label: "Done"
                onClicked: root.done()
            }
        }
    }

    WallpaperGrid {
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        rows: 3
        folder: root.folder
        files: root.files
        marked: root.marked
        badges: root.badges
        onPicked: path => root.picked(path)
    }
}
