import QtQuick
import qs.components as Components
import qs.singletons

// The public tooltip (module API 1.31): a short plain text shown after a moment's hover
// over `target` — by default the item it is written inside. It takes no room and never
// takes the target's clicks or hover. Above the target, below it when there is no room,
// over everything else in the window.
//
//   SmallButton { label: "Send"; HoverTip { text: "To every device of this account" } }
//   HoverTip { target: _icon; text: device.name }
//
// The text is shown as written (plain text), on lines as wide as the tooltip, line breaks
// as spaces, cut with "…" past 200 characters (ApiElementRules.tipText). An empty text
// shows nothing.
//
// A wrapper around the internal tooltip (components/HoverTip.qml): what is declared here
// is all a module can rely on.
Item {
    id: root

    property Item target: parent
    property string text

    // Not laid out: a layout skips a hidden item, and the tooltip lives in the window's top
    // item, not here
    visible: false
    width: 0
    height: 0

    HoverHandler {
        id: _hover
        parent: root.target
        enabled: root.target !== null
    }

    Components.HoverTip {
        target: root.target ?? root
        shown: _hover.hovered && root.target !== null && root.target.visible
        text: ApiElementRules.tipText(root.text)
    }
}
