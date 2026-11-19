import QtQuick

// One line of a popup panel (a VPN's row with what goes under it), as an anchor block
// (components/AnchorBlock.qml). Its root is a plain column: the `before` host, its body —
// its content, laid out in a column `spacing` apart — the `after` host; the parent sees one
// item, so it serves as a Repeater's delegate. A row repeated per item is named by its kind
// (`anchor: "row"`): all of them share one path, the item goes in its `context`.
//
//   delegate: PopupRow {
//       anchor: "row"
//       width: parent.width
//       spacing: 2
//       Rectangle { width: parent.width; … }    // the content: `width: parent.width` applies
//   }
AnchorBlock {
    id: root

    property real spacing: 0
    default property alias content: _body.data
    // The hosts, for the core's tests
    readonly property alias beforeHost: _before
    readonly property alias afterHost: _after

    kind: "row"
    placements: ["before", "after"]
    implicitHeight: _column.implicitHeight

    Column {
        id: _column
        width: root.width
        spacing: root.spacing

        AnchorContent {
            id: _before
            block: root
            placement: "before"
            width: parent.width
        }

        Column {
            id: _body
            width: parent.width
            spacing: root.spacing
        }

        AnchorContent {
            id: _after
            block: root
            placement: "after"
            width: parent.width
        }
    }
}
