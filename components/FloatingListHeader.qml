import QtQuick
import qs.singletons

// A group's title inside a FloatingList, above the group's first entry: not an entry, so
// the list's keys pass it by. Plain text, one line.
//
//   FloatingListHeader { text: "Theme colours" }
Text {
    readonly property bool floatingListHeader: true

    // A title the Repeater lets go of while everything goes has no parent any more
    width: parent ? parent.width : 0
    // Further in than an entry's text (6 px), so it does not read as one
    leftPadding: 10
    rightPadding: 6
    topPadding: 6
    bottomPadding: 2
    textFormat: Text.PlainText
    maximumLineCount: 1
    elide: Text.ElideRight
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeSmall
    font.weight: Theme.fontWeightBold
    color: Theme.textMuted
}
