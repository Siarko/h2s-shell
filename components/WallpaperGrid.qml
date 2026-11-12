import QtQuick
import Quickshell
import qs.singletons

// A folder's images as thumbnails to pick from (Wallpaper settings). A GridView: only the
// thumbnails in view (and a little beyond) exist, so a folder of hundreds opens at once and
// decodes as it scrolls; each is decoded small, in the background, and kept in Qt's cache.
// The owner says which are marked (`marked`: a check) and what each is used for
// (`badges`: short labels on it); a click is `picked(path)`.
Item {
    id: root

    // The folder, absolute, and its images relative to it
    property string folder: ""
    property var files: []
    // Paths shown with a check
    property var marked: []
    // { path: "label, label" } — where each image is used
    property var badges: ({})
    // How many rows show before it scrolls
    property int rows: 3
    signal picked(string path)

    readonly property real _cell: Math.max(96, Math.floor(width / Math.max(1, Math.round(width / 150))))
    readonly property real _scale: (QsWindow.window?.devicePixelRatio ?? 1)

    readonly property int _columns: Math.max(1, Math.floor(width / _cell))
    implicitHeight: Math.max(1, Math.min(rows, Math.ceil(files.length / _columns))) * Math.round(_cell * 0.66)

    function _url(path) {
        return "file://" + (folder + "/" + path).split("/").map(encodeURIComponent).join("/");
    }

    GridView {
        id: _grid
        anchors.fill: parent
        clip: true
        cellWidth: root._cell
        cellHeight: Math.round(root._cell * 0.66)
        cacheBuffer: cellHeight * 2
        boundsBehavior: Flickable.StopAtBounds
        // ScriptModel, never the bare array (CLAUDE.md)
        model: ScriptModel { values: root.files }

        delegate: Item {
            id: _cellItem
            required property string modelData
            readonly property bool _marked: root.marked.includes(modelData)
            readonly property string _badge: root.badges[modelData] ?? ""

            width: _grid.cellWidth
            height: _grid.cellHeight

            Rectangle {
                id: _frame
                anchors.fill: parent
                anchors.margins: 3
                radius: Theme.field.radius
                color: Theme.fillSubtle
                border.width: _cellItem._marked || _cellItem._badge !== "" ? Theme.border.selectedWidth : (_area.lit ? Theme.border.width : 0)
                border.color: _cellItem._marked || _cellItem._badge !== "" ? Theme.accent : Theme.outline
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: _frame.border.width
                    source: root._url(_cellItem.modelData)
                    sourceSize: Qt.size(width * root._scale, height * root._scale)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.duration("fade"); easing: Theme.curve("fade") } }
                }

                // Where it is used
                Rectangle {
                    visible: _cellItem._badge !== ""
                    anchors { left: parent.left; bottom: parent.bottom; margins: 4 }
                    width: Math.min(parent.width - 8, _badgeText.implicitWidth + 8)
                    height: _badgeText.implicitHeight + 2
                    radius: height / 2
                    color: Theme.accent
                    Text {
                        id: _badgeText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.parent.width - 16)
                        text: _cellItem._badge
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onAccent
                    }
                }

                // Chosen
                Rectangle {
                    visible: _cellItem._marked
                    anchors { right: parent.right; top: parent.top; margins: 4 }
                    width: 20
                    height: 20
                    radius: 10
                    color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        color: Theme.onAccent
                    }
                }
            }

            PointerArea {
                id: _area
                centred: false
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(_cellItem.modelData)
            }

            HoverTip {
                target: _cellItem
                shown: _area.containsMouse
                text: _cellItem.modelData
            }
        }
    }
}
