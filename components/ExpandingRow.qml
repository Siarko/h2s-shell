import QtQuick
import QtQuick.Layouts
import qs.singletons

// A line that opens: a label, a short line under it (`hint`) and the "▸" / "▾" of a card's
// header; a click anywhere on the line opens or closes it. What it opens is its child,
// held as a Component: built when the row opens, destroyed once it has slid shut, laid out
// at the row's width under the line — sliding open and shut as every part that opens on a
// settings page (Reveal).
//
//   ExpandingRow { label: "Exit node"; hint: "None"; ExitNodeList {} }
ColumnLayout {
    id: root

    property string label: ""
    property string hint: ""
    property bool open: false
    default property Component content

    Layout.fillWidth: true
    spacing: 6

    // The click area goes under the line, as on a card's header
    Item {
        Layout.fillWidth: true
        implicitWidth: _line.implicitWidth
        implicitHeight: _line.implicitHeight

        PointerArea {
            centred: false
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open = !root.open
        }

        RowLayout {
            id: _line
            width: parent.width
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: root.label
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    color: Theme.textPrimary
                }
                Text {
                    visible: root.hint !== ""
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.hint
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textMuted
                }
            }
            Text {
                Layout.alignment: Qt.AlignTop
                text: root.open ? "▾" : "▸"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textMuted
            }
        }
    }

    Reveal {
        id: _reveal
        open: root.open

        Loader {
            objectName: "expandingContent"
            Layout.fillWidth: true
            // Kept while it slides shut, so what it holds goes with the slide
            active: root.open || _reveal.shown
            sourceComponent: root.content
        }
    }
}
