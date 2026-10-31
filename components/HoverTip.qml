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
    // Where on the target to point at, in its coordinates — Qt.rect(x, top, 0, height) of a
    // line, say (a link under the pointer); null for the whole target
    property var anchorRect: null

    parent: target?.Window.window?.contentItem ?? target
    z: 1000
    visible: false
    width: Math.min(_text.implicitWidth, maxWidth) + 2 * Theme.tooltip.horizontalPadding
    height: _text.implicitHeight + 2 * Theme.tooltip.verticalPadding
    radius: Theme.tooltip.radius
    color: Theme.surface
    border.color: Theme.textDisabled
    border.width: Theme.border.width

    // Shown and with something to say, both read together: the two often change at once
    // (a hovered link and its address), and a handler of one alone could still see the
    // other's old value — the tip then never opened
    readonly property bool _wanted: shown && text !== ""
    on_WantedChanged: {
        if (_wanted) {
            _delay.restart();
        } else {
            _delay.stop();
            visible = false;
        }
    }

    // Placed when it opens (the target does not move while hovered), and again when its
    // text changes while open — the pointer moved straight onto another link
    onTextChanged: if (visible && text !== "") _place()
    function _place() {
        const area = anchorRect ?? Qt.rect(0, 0, target.width, target.height);
        const centre = area.x + area.width / 2;
        const below = target.mapToItem(parent, centre, area.y + area.height);
        const above = target.mapToItem(parent, centre, area.y);
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
        x: Theme.tooltip.horizontalPadding
        y: Theme.tooltip.verticalPadding
        width: Math.min(implicitWidth, root.maxWidth)
        text: root.text
        // At spaces where there are some, anywhere in a long run without (an address)
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeBody
        color: Theme.textPrimary
    }
}
