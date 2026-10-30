import QtQuick

// Takes the keyboard focus away from a field when a click lands anywhere else in the
// window — on the background too, not only on another control. Lies over the content,
// filling its parent, and lets every press through untouched, so whatever is under it
// works as before. A press on the focused field itself leaves its focus be (placing the
// cursor must not finish the edit).
MouseArea {
    id: root

    anchors.fill: parent
    acceptedButtons: Qt.AllButtons

    onPressed: mouse => {
        const focused = Window.activeFocusItem;
        if (focused && focused !== root) {
            const point = mapToItem(focused, mouse.x, mouse.y);
            if (!focused.contains(point))
                root.forceActiveFocus();
        }
        mouse.accepted = false;
    }
}
