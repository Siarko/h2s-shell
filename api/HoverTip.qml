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

    // The hover over the target: a handler on the target, owned here — made when the
    // target is set, destroyed with this tooltip or when the target changes, so tooltips
    // made again and again against one item leave no handlers behind on it. A target
    // destroyed takes its handler with it; the reference then reads null.
    QtObject {
        id: _hover
        property HoverHandler handler: null
        function attach() {
            if (handler)
                handler.destroy();
            handler = root.target ? _handlerMaker.createObject(root.target, { parent: root.target }) : null;
        }
    }
    Component {
        id: _handlerMaker
        HoverHandler {}
    }
    onTargetChanged: _hover.attach()
    Component.onCompleted: _hover.attach()
    Component.onDestruction: if (_hover.handler) _hover.handler.destroy()

    Components.HoverTip {
        target: root.target ?? root
        shown: root.target !== null && _hover.handler !== null && _hover.handler.hovered && root.target.visible
        text: ApiElementRules.tipText(root.text)
    }
}
