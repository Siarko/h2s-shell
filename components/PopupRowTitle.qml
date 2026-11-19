import QtQuick
import QtQuick.Layouts
import qs.singletons

// A popup row's name (a network's in the network popup), with the row's region `title`
// (<row>.title, components/AnchorBlock.qml) on its line: modules' elements right after the
// name, `append`, side by side in the one order, each as tall as the line (given its height,
// cut to it), at most `maxElementWidth` all together (a quarter of the row), cut on the
// right. Room is kept for them in the name's right padding, and the name's least width is
// that room, so the name is cut first and the elements stay inside the name's part of the
// row. With no element the name stands as a plain Text would. Inside a row block named
// "row" (PopupRow) it is that row's place; anywhere else (a row with no name) it is none.
//
//   RowLayout {
//       PopupRowTitle {
//           Layout.fillWidth: true
//           text: network.ssid
//           maxElementWidth: Math.floor(row.width / 4)
//           context: row.context
//           font.pixelSize: Theme.fontSizeBodyLarge
//       }
//   }
Text {
    id: root

    // What its elements get as `context`: the row's
    property var context: ({})
    // The most its elements take, all together
    property real maxElementWidth: Infinity
    // The region and its host, for the core's tests
    readonly property alias titleRegion: _region
    readonly property alias appendHost: _append

    Layout.minimumWidth: rightPadding
    elide: Text.ElideRight
    textFormat: Text.PlainText
    font.family: Theme.fontFamily
    color: Theme.textPrimary
    rightPadding: _region.width > 0 ? _region.width + _region.gap : 0

    AnchorBlock {
        id: _region

        readonly property alias appendHost: _append
        readonly property real gap: 6

        // Right after the name as drawn: its whole width, or what is left of the line beside
        // the elements — on its right end when it is drawn on the right (a right-to-left name)
        x: (root.effectiveHorizontalAlignment === Text.AlignLeft
            ? Math.max(0, Math.min(root.implicitWidth, root.width) - root.rightPadding)
            : root.width - root.rightPadding) + gap
        width: Math.min(_append.implicitWidth, root.maxElementWidth)
        height: root.height
        clip: true
        anchor: "title"
        kind: "region"
        placements: ["append"]
        context: root.context

        AnchorContent {
            id: _append
            block: _region
            placement: "append"
            inline: true
            elementHeight: root.height
            maxElementWidth: root.maxElementWidth
            height: root.height
        }
    }
}
