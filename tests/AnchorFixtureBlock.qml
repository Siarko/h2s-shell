import QtQuick
import qs.components

// A block of the fixture view (tests/AnchorsTest.qml) with a host at each of the four
// placements: its root a plain column — the `before` host, its body (a frame line, then the
// `prepend` host, its content, the `append` host), the `after` host — so the order of
// placements around and inside a block is checked before the shell's own kinds with all four
// exist.
AnchorBlock {
    id: root

    property string title: "Box"
    default property alias content: _content.data
    readonly property alias beforeHost: _before
    readonly property alias prependHost: _prepend
    readonly property alias appendHost: _append
    readonly property alias afterHost: _after
    readonly property alias frame: _frame

    kind: "section"
    placements: ["before", "after", "prepend", "append"]
    implicitWidth: 300
    implicitHeight: _column.implicitHeight

    Column {
        id: _column
        width: root.width

        AnchorContent {
            id: _before
            block: root
            placement: "before"
            width: parent.width
        }

        Column {
            width: parent.width

            Text {
                id: _frame
                text: root.title
                textFormat: Text.PlainText
            }

            AnchorContent {
                id: _prepend
                block: root
                placement: "prepend"
                width: parent.width
            }

            Column {
                id: _content
                width: parent.width
            }

            AnchorContent {
                id: _append
                block: root
                placement: "append"
                width: parent.width
            }
        }

        AnchorContent {
            id: _after
            block: root
            placement: "after"
            width: parent.width
        }
    }
}
