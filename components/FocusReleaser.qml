import QtQuick

// Takes the keyboard focus away from a field when a click lands anywhere else in the
// window — on the background too, not only on another control. Lies over the content,
// filling its parent, and only watches presses: a PointHandler, passive, so whatever is
// under it takes the press as before. Not a MouseArea: a MouseArea always sets a cursor
// (the arrow), and over everything it hid the controls' own cursors. A press on the
// focused field itself leaves its focus be (placing the cursor must not finish the edit).
Item {
    id: root

    anchors.fill: parent

    PointHandler {
        acceptedButtons: Qt.AllButtons
        onActiveChanged: {
            if (!active)
                return;
            const focused = root.Window.activeFocusItem;
            if (!focused || focused === root)
                return;
            const inFocused = root.mapToItem(focused, point.position.x, point.position.y);
            if (!focused.contains(inFocused))
                root.forceActiveFocus();
        }
    }
}
