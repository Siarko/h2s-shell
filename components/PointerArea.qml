import QtQuick
import qs.singletons

// The MouseArea of a control that looks different under the pointer — for a mouse and a
// finger alike (TODO 11.11, 11.14):
//
// - `lit` instead of `containsMouse` for that look. A finger is "over" a control only
//   while it presses (Qt synthesises the mouse from it: in on the press, out on the
//   release), and a tap is over in about 80 ms — less than the colour takes to change.
//   `lit` holds on for a moment after the release, so a tap is seen. For a mouse nothing
//   changes: the pointer is still over the control after a click.
// - At least Theme.target.minSize across and down, centred on its parent, past the
//   control's look when that is smaller: a click or a tap just beside a small control
//   still reaches it. The look and the layout stay as they are. Where controls sit closer
//   than that, the one above (later) takes the overlap.
//
// `hoverEnabled` on. `centred: false` leaves the size and place to the user's own anchors
// (an area that is not its parent's whole box): no larger target then.
MouseArea {
    id: root

    readonly property bool lit: containsMouse || pressed || _lingering
    // How long the look stays after a press ends, in ms
    property int linger: 200
    property bool centred: true
    // How far past its parent it reaches at least, on every side — more than the least
    // target where a control asks for it
    property real reach: 0

    property bool _lingering: false

    anchors.centerIn: centred ? parent : undefined
    width: centred ? Math.max((parent ? parent.width : 0) + 2 * reach, Theme.target.minSize) : implicitWidth
    height: centred ? Math.max((parent ? parent.height : 0) + 2 * reach, Theme.target.minSize) : implicitHeight
    hoverEnabled: true

    onPressedChanged: {
        if (pressed) {
            _lingerTimer.stop();
            _lingering = false;
        } else {
            _lingering = true;
            _lingerTimer.restart();
        }
    }

    Timer {
        id: _lingerTimer
        interval: root.linger
        onTriggered: root._lingering = false
    }
}
