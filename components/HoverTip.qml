import QtQuick
import qs.singletons

// A small explanatory tooltip for `target`, shown after a short hover. It lives in the
// window's top-level item rather than next to the target, so a clipping parent (a
// scrolling settings page) cannot cut it off. Above the target by default, below it when
// there is no room; kept inside the window horizontally.
//
//   HoverTip { target: pinButton; shown: pinArea.containsMouse; text: "…" }
Rectangle {
    id: root

    required property Item target
    property string text: ""
    // Usually the target's hover state
    property bool shown: false
    property int delay: 500
    property int maxWidth: 260

    parent: target?.Window.window?.contentItem ?? target
    z: 1000
    visible: false
    width: Math.min(_text.implicitWidth, maxWidth) + 16
    height: _text.implicitHeight + 12
    radius: 4
    color: Theme.cellDefault
    border.color: Theme.textDim
    border.width: 1

    onShownChanged: {
        if (shown && text !== "") {
            _delay.restart();
        } else {
            _delay.stop();
            visible = false;
        }
    }

    // Placed when it opens; the target does not move while hovered
    function _place() {
        const below = target.mapToItem(parent, target.width / 2, target.height);
        const above = target.mapToItem(parent, target.width / 2, 0);
        x = Math.max(4, Math.min(parent.width - width - 4, above.x - width / 2));
        y = above.y - height - 6 >= 0 ? above.y - height - 6 : below.y + 6;
    }

    Timer {
        id: _delay
        interval: root.delay
        onTriggered: {
            root._place();
            root.visible = true;
        }
    }

    Text {
        id: _text
        x: 8
        y: 6
        width: Math.min(implicitWidth, root.maxWidth)
        text: root.text
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textPrimary
    }
}
