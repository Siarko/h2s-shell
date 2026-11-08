import QtQuick
import QtQuick.Layouts
import qs.singletons

// A link's download/upload speeds; clicking the row shows or hides their history graph.
// While the graph is open the arrows take the colours of their lines, as its legend.
Column {
    id: root

    property real rxSpeed: 0
    property real txSpeed: 0
    property var rxHistory: []
    property var txHistory: []
    property bool expanded: false

    readonly property int _graphAreaHeight: 6 + _chart.implicitHeight

    function _arrow(glyph, color) {
        return root.expanded ? "<font color=\"" + color + "\">" + glyph + "</font>" : glyph;
    }

    Item {
        width: parent.width
        height: _speeds.implicitHeight

        // Hover highlight, reaching a little past the text so it does not touch the edges
        Rectangle {
            anchors {
                fill: parent
                leftMargin: -4
                rightMargin: -4
                topMargin: -2
                bottomMargin: -2
            }
            radius: Theme.listItem.radius
            color: _rowArea.lit ? Theme.surfaceHover : Theme.surfaceHoverClear
            Behavior on color { ColorAnimation { duration: Theme.duration("hover"); easing: Theme.curve("hover") } }
        }

        RowLayout {
            id: _speeds
            width: parent.width

            Text {
                text: root._arrow("↓", Theme.accent) + " " + Format.rate(root.rxSpeed)
                textFormat: Text.StyledText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
                Layout.fillWidth: true
            }

            Text {
                text: root._arrow("↑", Theme.accentSecondary) + " " + Format.rate(root.txSpeed)
                textFormat: Text.StyledText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody
                color: Theme.textSecondary
            }
        }

        PointerArea {
            id: _rowArea
            centred: false
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }
    }

    // Graph area, always present and clipped, so opening it animates
    Item {
        width: parent.width
        height: root.expanded ? root._graphAreaHeight : 0
        clip: true

        Behavior on height { NumberAnimation { duration: Theme.duration("expand"); easing: Theme.curve("expand") } }

        HistoryChart {
            id: _chart
            y: 6
            width: parent.width
            active: root.expanded
            series: [
                { history: root.rxHistory, color: Theme.accent },
                { history: root.txHistory, color: Theme.accentSecondary }
            ]
            formatPeak: Format.rate
        }
    }
}
