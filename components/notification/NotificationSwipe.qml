import QtQuick
import qs.components
import qs.singletons

// A notification card swiped away with a finger, as on Android (NotificationCard). Dragged
// sideways the card follows the finger and fades; let go past a third of its width, or
// flung, it goes on out that way and asks to be dismissed (the card's `swipedAway` set, so
// the owner skips its own slide out); short of that it comes back. A finger only: the mouse
// keeps selecting text and its dismiss button. This overlay above the card's content
// watches (the press reaches the buttons, the reply and the text beneath), taking the touch
// only once it moves sideways.
Item {
    id: root

    // The card it moves (NotificationCard)
    required property Item card
    readonly property bool active: _swipe.active

    // A new notification in the card: no swipe goes on
    function stop() {
        _swipeBack.stop();
        _swipeOut.stop();
    }

    anchors.fill: parent
    z: 20

    SwipeGesture {
        id: _swipe
        yAxis.enabled: false
        property real _restX: 0
        onActiveChanged: {
            if (active) {
                _swipeBack.stop();
                _restX = root.card.x;
                return;
            }
            if (meant(deltaX, velocity().x, root.card.width / 3)) {
                _swipeOut.to = _restX + (deltaX > 0 ? 1 : -1) * root.card.width * 1.2;
                _swipeOut.start();
            } else {
                _swipeBack.to = _restX;
                _swipeBack.start();
            }
        }
        onDeltaXChanged: {
            if (!active)
                return;
            root.card.x = _restX + deltaX;
            root.card.opacity = Math.max(0.2, 1 - Math.abs(deltaX) / root.card.width);
        }
    }

    ParallelAnimation {
        id: _swipeBack
        property alias to: _backX.to
        NumberAnimation { id: _backX; target: root.card; property: "x"; duration: Theme.duration("move"); easing: Theme.curve("move") }
        NumberAnimation { target: root.card; property: "opacity"; to: 1; duration: Theme.duration("move"); easing: Theme.curve("move") }
    }

    ParallelAnimation {
        id: _swipeOut
        property alias to: _outX.to
        NumberAnimation { id: _outX; target: root.card; property: "x"; duration: Theme.duration("exit"); easing: Theme.curve("exit") }
        NumberAnimation { target: root.card; property: "opacity"; to: 0; duration: Theme.duration("exit"); easing: Theme.curve("exit") }
        onFinished: {
            root.card.swipedAway = true;
            root.card.closeClicked();
            root.card.dismissRequested();
        }
    }
}
