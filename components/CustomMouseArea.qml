import QtQuick

// A MouseArea that also reports the wheel in whole notches (ScrollNotches)
MouseArea {
    id: root

    // Emitted for each whole notch, 1 for up, -1 for down
    signal scrollNotchY(int direction)

    readonly property ScrollNotches _notches: ScrollNotches {}

    onWheel: event => {
        const direction = root._notches.feed(event.angleDelta.y);
        if (direction !== 0)
            root.scrollNotchY(direction);
    }
}
