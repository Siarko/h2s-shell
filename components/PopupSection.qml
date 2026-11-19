import QtQuick
import qs.singletons

// A group in a popup panel, as an anchor block (components/AnchorBlock.qml); a panel's root
// is one too, the place popup.<key> its popup gives it. Its root is a plain column: the
// `before` host, its frame's header line (`header`, a Component), the `prepend` host, its
// content, the `append` host, its closing divider (`divider`), the `after` host — so the
// parent sees one item, in a Column or as a Repeater's delegate. The content is laid out in a
// column `spacing` apart, and so are the frame and the hosts around it: what is hidden, or
// has no height, takes no room and no spacing, as in a Column.
//
//   PopupSection {
//       anchor: "connections"
//       width: parent.width
//       spacing: 6
//       divider: WifiManager.wifiEnabled
//       context: ({ wifiEnabled: WifiManager.wifiEnabled })
//       RowLayout { width: parent.width; … }      // the content: `width: parent.width` applies
//   }
//
// `fillHeight`: given a height (a panel's root, anchors.fill), its content gets what the
// frame and the hosts leave, so one item there may take `height: parent.height` (a list).
AnchorBlock {
    id: root

    // The header line, above its content ("" none): a Component, built as wide as the block
    property Component header: null
    // The closing line under its content
    property bool divider: false
    property real spacing: 0
    // How far its prepend and append elements stand in from its sides
    property real inset: 0
    property bool fillHeight: false
    default property alias content: _content.data
    // Where its content starts, from its top (what stands above it: the before host, the
    // header, the prepend host)
    readonly property real contentTop: _area.y
    // The hosts, for the core's tests
    readonly property alias beforeHost: _before
    readonly property alias prependHost: _prepend
    readonly property alias appendHost: _append
    readonly property alias afterHost: _after

    kind: "popupSection"
    placements: ["before", "after", "prepend", "append"]
    implicitHeight: fillHeight ? 0 : _column.implicitHeight

    // With fillHeight: the room the column's other items take, each with its spacing
    readonly property real _othersHeight: {
        let total = 0;
        for (const item of [_before, _header, _prepend, _append, _divider, _after]) {
            if (item.visible && item.height > 0)
                total += item.height + spacing;
        }
        return total;
    }

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

        // The frame: never content, so a prepended element comes under it
        Loader {
            id: _header
            width: parent.width
            active: root.header !== null
            visible: active
            sourceComponent: root.header
        }

        AnchorContent {
            id: _prepend
            block: root
            placement: "prepend"
            x: root.inset
            width: parent.width - 2 * root.inset
        }

        Item {
            id: _area
            width: parent.width
            height: root.fillHeight ? Math.max(0, root.height - root._othersHeight) : _content.implicitHeight

            Column {
                id: _content
                width: parent.width
                height: root.fillHeight ? parent.height : implicitHeight
                spacing: root.spacing
            }
        }

        AnchorContent {
            id: _append
            block: root
            placement: "append"
            x: root.inset
            width: parent.width - 2 * root.inset
        }

        Rectangle {
            id: _divider
            visible: root.divider
            width: parent.width
            height: 1
            color: Theme.textDisabled
            opacity: 0.3
        }

        AnchorContent {
            id: _after
            block: root
            placement: "after"
            width: parent.width
        }
    }
}
